#!/usr/bin/env python3
"""
s01_data_sync_video.py
-----------------------
Unified BIDS Multi-Camera Video Synchronization & Slicing Pipeline.
Parses master LSL XDF files, aligns camera frame markers, applies hardware lag 
compensation, and exports cropped BIDS videos (.mp4), JSON sidecars, and TSV frame LUTs.
"""

import argparse
import json
import os
import glob
import re
import cv2
import numpy as np
import pandas as pd
import pyxdf


def parse_args():
    parser = argparse.ArgumentParser(description="BIDS Tri-Camera Video Synchronizer & Slicer")
    parser.add_argument("--sub", required=True, help="Subject ID (e.g., MH9HXJ or sub-MH9HXJ)")
    parser.add_argument("--ses", required=True, help="Session ID (e.g., S001 or ses-S001)")
    parser.add_argument("--run", default="all", help="Run ID ('all' to process all runs, or e.g., '001')")
    parser.add_argument("--task", default="heightaffordance", help="Task name [default: heightaffordance]")
    parser.add_argument("--pre-offset", type=float, default=3.0, help="Buffer (s) before TrialOffset [default: 3.0]")
    parser.add_argument("--data-root", default=os.environ.get("DLC_DATA_ROOT", "/mnt/beegfs/home/nguyen/1223-xplo-judo/10_Data/"),
                        help="Root dataset directory")
    return parser.parse_args()


def adjust_frame(frame, contrast=1.4, brightness=0.35, gamma=(1.0 / 1.1)):
    """Applies contrast, brightness, and gamma transformations using Numpy vectorization."""
    img_float = frame.astype(np.float32) / 255.0
    img_proc = (img_float - 0.5) * contrast + 0.5 + brightness
    img_proc = np.power(np.maximum(img_proc, 0), gamma)
    return (np.clip(img_proc * 255.0, 0, 255)).astype(np.uint8)


def extract_trials(m_text, m_time, pre_offset_reduction):
    """Parses LSL trigger stream for Neutral start markers and TrialOffset end markers."""
    trials = []
    trial_count = 0
    active_start_ts = None

    for text, ts in zip(m_text, m_time):
        if text == f"Neutral{trial_count + 1}":
            active_start_ts = ts
        elif "TrialOffset" in text and active_start_ts is not None:
            calc_end_ts = ts - pre_offset_reduction
            if calc_end_ts > active_start_ts:
                trial_count += 1
                trials.append({
                    "trial_id": trial_count,
                    "start_ts": active_start_ts,
                    "end_ts": calc_end_ts
                })
            else:
                print(f"  WARNING: Skipping trial {trial_count + 1}: reduction buffer made window invalid.")
            active_start_ts = None

    return trials


def process_run(sub_id, ses_id, run_id, task_name, paths, pre_offset):
    print(f"\n================ Processing {sub_id} | {ses_id} | run-{run_id} ================")
    
    search_prefix = f"{sub_id}_{ses_id}_task-{task_name}_run-{run_id}"
    xdf_path = os.path.join(paths["lsl_dir"], f"{search_prefix}_lslglobal.xdf")
    
    if not os.path.exists(xdf_path):
        print(f"  ! Master XDF file not found: {xdf_path}")
        return

    print("  Loading LSL streams from XDF...")
    streams, _ = pyxdf.load_xdf(xdf_path)

    # Locate trigger/marker stream
    marker_stream = None
    frame_markers = {}
    
    for stream in streams:
        name = stream["info"]["name"][0]
        if "Trigger" in name or "Markers" in name:
            marker_stream = stream
        elif "FrameMarker_1" in name:
            frame_markers["SideView"] = stream
        elif "FrameMarker_0" in name:
            frame_markers["UpperView"] = stream
        elif "FrameMarker_2" in name:
            frame_markers["GroundView"] = stream

    if not marker_stream:
        print("  ! Error: Marker event stream missing in XDF.")
        return

    m_text = [item[0] for item in marker_stream["time_series"]]
    m_time = np.array(marker_stream["time_stamps"])

    trials = extract_trials(m_text, m_time, pre_offset)
    if not trials:
        print("  ! Error: No valid trials extracted from marker stream.")
        return
    print(f"  Extracted {len(trials)} valid trials.")

    # Automatically discover all available raw video camera views for this run
    video_search = os.path.join(paths["video_dir"], f"{search_prefix}_acq-*_beh.avi")
    found_videos = glob.glob(video_search)
    
    if not found_videos:
        # Fallback search for .mp4 formats
        video_search = os.path.join(paths["video_dir"], f"{search_prefix}_acq-*_beh.mp4")
        found_videos = glob.glob(video_search)

    if not found_videos:
        print(f"  ! No camera video files found for run {run_id} in {paths['video_dir']}")
        return

    camera_views = {}
    for vid_path in found_videos:
        match = re.search(r'acq-([A-Za-z0-9]+)_beh', vid_path)
        if match:
            camera_views[match.group(1)] = vid_path

    print(f"  Found {len(camera_views)} camera views: {list(camera_views.keys())}")

    # Camera processing configurations
    contrast_vals = {"SideView": 1.4, "UpperView": 1.4, "GroundView": 1.4}
    brightness_vals = {"SideView": 0.35, "UpperView": 0.35, "GroundView": 0.35}
    hardware_frame_lag = 10
    event_display_window = 0.5

    for trial in trials:
        t_id = trial["trial_id"]
        t_start = trial["start_ts"]
        t_end = trial["end_ts"]
        t_dur = t_end - t_start
        base_out_name = f"{sub_id}_{ses_id}_task-{task_name}_run-{run_id}_trial-{t_id:03d}"

        print(f"  -> Trial {t_id:03d}/{len(trials):03d} (Duration: {t_dur:.2f}s)")

        # Extract trial event markers
        mask = (m_time >= t_start) & (m_time <= t_end)
        t_marker_texts = np.array(m_text)[mask]
        t_marker_times = m_time[mask]

        for cam_label, vid_path in camera_views.items():
            cap = cv2.VideoCapture(vid_path)
            if not cap.isOpened():
                print(f"    ! Error opening video stream: {vid_path}")
                continue

            fps = cap.get(cv2.CAP_PROP_FPS)
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

            out_video_path = os.path.join(paths["output_dir"], f"{base_out_name}_acq-{cam_label}_beh.mp4")
            out_json_path = os.path.join(paths["output_dir"], f"{base_out_name}_acq-{cam_label}_beh.json")
            out_tsv_path = os.path.join(paths["output_dir"], f"{base_out_name}_acq-{cam_label}_desc-frameLUT_beh.tsv")

            # Resolve frame ranges via LSL stream
            stream = frame_markers.get(cam_label)
            if stream is not None:
                v_frames = np.array([item[0] for item in stream["time_series"]])
                v_time = np.array(stream["time_stamps"])
                
                neutral_idx = np.argmin(np.abs(v_time - t_start))
                end_idx = np.argmin(np.abs(v_time - t_end))

                start_frame = int(v_frames[neutral_idx]) + hardware_frame_lag
                end_frame = int(v_frames[end_idx]) + hardware_frame_lag
                trial_lsl_start_ts = v_time[neutral_idx]
            else:
                start_frame = max(1, int(round((t_start - m_time[0]) * fps)) + hardware_frame_lag)
                end_frame = min(total_frames, int(round((t_end - m_time[0]) * fps)) + hardware_frame_lag)
                trial_lsl_start_ts = t_start
                v_frames = np.arange(1, total_frames + 1)
                v_time = (np.arange(0, total_frames) / fps) + t_start

            start_frame = max(1, min(start_frame, total_frames))
            end_frame = max(start_frame, min(end_frame, total_frames))

            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            writer = cv2.VideoWriter(out_video_path, fourcc, fps, (width, height))

            cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame - 1)
            current_frame_num = start_frame
            frame_lut_data = []
            lut_row_idx = 0

            contrast = contrast_vals.get(cam_label, 1.4)
            brightness = brightness_vals.get(cam_label, 0.35)

            while cap.isOpened() and (current_frame_num <= end_frame):
                ret, frame = cap.read()
                if not ret:
                    break

                physical_frame_num = current_frame_num - hardware_frame_lag
                lsl_matches = np.where(v_frames == physical_frame_num)[0]
                lsl_idx = lsl_matches[0] if len(lsl_matches) > 0 else np.argmin(np.abs(v_frames - physical_frame_num))

                global_lsl_ts = v_time[lsl_idx]
                elapsed_trial_time = global_lsl_ts - trial_lsl_start_ts
                python_frame_idx = lut_row_idx

                frame_lut_data.append([python_frame_idx, global_lsl_ts, elapsed_trial_time])

                # Color processing
                frame_proc = adjust_frame(frame, contrast=contrast, brightness=brightness)

                # Overlays
                lbl_text = f"Trial: {t_id:03d} | Frame: {python_frame_idx} | Time: {elapsed_trial_time:.2f}s"
                cv2.putText(frame_proc, lbl_text, (15, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2, cv2.LINE_AA)

                active_events = np.where((global_lsl_ts >= t_marker_times) & (global_lsl_ts <= (t_marker_times + event_display_window)))[0]
                if len(active_events) > 0:
                    evt_str = f"EVENT: {t_marker_texts[active_events[0]]}"
                    cv2.putText(frame_proc, evt_str, (int(width / 2 - 150), 60), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 255), 2, cv2.LINE_AA)

                writer.write(frame_proc)
                current_frame_num += 1
                lut_row_idx += 1

            cap.release()
            writer.release()

            # Save TSV LUT
            df_lut = pd.DataFrame(frame_lut_data, columns=["video_frame", "raw_lsl_timestamp", "elapsed_trial_time"])
            df_lut.to_csv(out_tsv_path, sep="\t", index=False)

            # Save BIDS Sidecar JSON
            sidecar = {
                "SpatialReference": f"Native camera frame space pixel matrix ({width}x{height})",
                "RawSourceFile": os.path.basename(vid_path),
                "TrialID": t_id,
                "FrameRate": fps,
                "TargetAnalysisEngine": "DeepLabCut Pose Estimation",
                "TemporalAlignment": {
                    "TimeSynchronizedVia": f"LSL FrameMarker mapping ({cam_label})",
                    "LookupTableFile": os.path.basename(out_tsv_path),
                    "StartMarker": "NPose",
                    "EndMarker": "TrialOffset Reduction Buffer window"
                }
            }
            with open(out_json_path, "w") as f:
                json.dump(sidecar, f, indent=4)


def main():
    args = parse_args()
    
    sub_label = re.sub(r'^sub-', '', args.sub)
    ses_label = re.sub(r'^ses-', '', args.ses)
    sub_id = f"sub-{sub_label}"
    ses_id = f"ses-{ses_label}"

    data_root = args.data_root
    lsl_dir = os.path.join(data_root, "sourcedata", sub_id, ses_id, "lslglobal")
    video_dir = os.path.join(data_root, "sourcedata", sub_id, ses_id, "video")
    output_dir = os.path.join(data_root, "derivatives", "syncdata", sub_id, ses_id, "video")
    
    os.makedirs(output_dir, exist_ok=True)

    paths = {
        "lsl_dir": lsl_dir,
        "video_dir": video_dir,
        "output_dir": output_dir
    }

    # Handle single run vs all available runs
    if args.run.lower() == "all":
        xdf_pattern = os.path.join(lsl_dir, f"{sub_id}_{ses_id}_task-{args.task}_run-*_lslglobal.xdf")
        xdf_files = glob.glob(xdf_pattern)
        if not xdf_files:
            raise FileNotFoundError(f"No XDF files found matching pattern: {xdf_pattern}")
        
        run_ids = []
        for filepath in sorted(xdf_files):
            match = re.search(r'run-(\d+)_lslglobal\.xdf', filepath)
            if match:
                run_ids.append(match.group(1))
        print(f"Discovered {len(run_ids)} run(s) for {sub_id} {ses_id}: {run_ids}")
    else:
        run_ids = [str(args.run).zfill(3)]

    for run_id in run_ids:
        process_run(sub_id, ses_id, run_id, args.task, paths, args.pre_offset)

    print(f"\nCompleted video sync and slicing. All derivatives exported to:\n{output_dir}")


if __name__ == "__main__":
    main()