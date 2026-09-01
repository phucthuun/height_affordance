import os
import tkinter as tk
from tkinter import filedialog
import cv2
import numpy as np
import openpyxl
import pandas as pd
import pyxdf


# =========================
# FILE PICKER
# =========================
def select_file(title, filetypes):
    print(f"[1/8] Opening file selector: {title}")
    root = tk.Tk()
    root.withdraw()
    path = filedialog.askopenfilename(title=title, filetypes=filetypes)
    if path:
        print(f"      Selected: {path}")
    else:
        print("      No file selected.")
    return path


# =========================
# LOAD XDF
# =========================
def load_xdf(path):
    print("[2/8] Loading XDF file...")
    print(f"      File: {path}")
    data, _ = pyxdf.load_xdf(path)
    print("      XDF loaded successfully.")
    print(f"      Number of streams found: {len(data)}")
    return data


def get_stream(streams, name):
    print(f"      Searching for stream: '{name}'")
    matches = [s for s in streams if s["info"]["name"][0] == name]
    print(f"      Found {len(matches)} matching stream(s).")
    return matches


# =========================
# PARSE EVENTS
# =========================
def parse_events(event_stream):
    print("[3/8] Parsing event markers...")
    markers = [
        s[0] if isinstance(s, list) else str(s)
        for s in event_stream["time_series"]
    ]
    times = np.array(event_stream["time_stamps"])
    events = list(zip(times, markers))
    print(f"      Parsed {len(events)} events.")
    print("\n      EVENT MARKERS:")
    print("      ------------------------------")
    for t, marker in events:
        print(f"      {t:.3f} sec    {marker}")
    print("      ------------------------------\n")
    return events


# =========================
# PARSE GAZE
# =========================
def parse_gaze(gaze_stream):
    print("[4/8] Parsing gaze data...")
    times = np.array(gaze_stream["time_stamps"])
    data = gaze_stream["time_series"]
    x, y = [], []
    for d in data:
        try:
            x.append(float(d[0]))
            y.append(float(d[1]))
        except:
            x.append(np.nan)
            y.append(np.nan)
    x = np.array(x)
    y = np.array(y)
    print(f"      Gaze samples: {len(times)}")
    print(f"      Valid X values: {np.sum(~np.isnan(x))}")
    print(f"      Valid Y values: {np.sum(~np.isnan(y))}")

    if len(times) > 0:
        print(
            f"      Gaze time range: " f"{times[0]:.6f} → {times[-1]:.6f} sec"
        )
    return times, x, y


# =========================
# EXPORT CALIBRATION GAZE
# =========================
def export_calibration_gaze(events, gaze_t, gx, gy, raw_gaze_t, out_dir):
    print("\n[EXOPTION] Exporting calibration gaze data to Excel...")

    cal_start = None
    cal_stop = None

    for t, marker in events:
        if "Neon_calibration_start" in marker:
            cal_start = t
        elif "Neon_calibration_stop" in marker:
            cal_stop = t

    if cal_start is None or cal_stop is None:
        print(
            "      WARNING: Calibration start or stop event marker not found."
            " Skipping Excel export."
        )
        return

    if cal_start > cal_stop:
        print(
            "      WARNING: Calibration start time is after stop time."
            " Skipping Excel export."
        )
        return

    mask = (gaze_t >= cal_start) & (gaze_t <= cal_stop)

    filtered_time_aligned = gaze_t[mask]
    filtered_time_raw = raw_gaze_t[mask]
    filtered_x = gx[mask]
    filtered_y = gy[mask]

    print(
        f"      Calibration window: {cal_start:.3f} sec → {cal_stop:.3f} sec"
    )
    print(f"      Found {np.sum(mask)} gaze samples during calibration.")

    if np.sum(mask) == 0:
        print("      No gaze samples found within the calibration window.")
        return

    df = pd.DataFrame({
        "Timestamp_Aligned_sec": filtered_time_aligned,
        "Timestamp_Raw_sec": filtered_time_raw,
        "Gaze_X": filtered_x,
        "Gaze_Y": filtered_y,
    })

    excel_path = os.path.join(out_dir, "calibration_gaze_data.xlsx")
    df.to_excel(excel_path, index=False)
    print(f"      Calibration gaze data saved to: {excel_path}\n")


# =========================
# NEAREST GAZE SAMPLE (NO INTERPOLATION)
# =========================
def get_nearest_gaze(t, gaze_t, gx, gy, max_dt=0.033):
    """Finds the raw recorded gaze sample nearest to timestamp 't' without spatial interpolation.

    Returns None if no sample falls within max_dt seconds.
    """
    if len(gaze_t) == 0:
        return None

    idx = np.argmin(np.abs(gaze_t - t))
    dt = abs(gaze_t[idx] - t)

    if dt <= max_dt:
        x_val, y_val = gx[idx], gy[idx]
        if not np.isnan(x_val) and not np.isnan(y_val):
            return x_val, y_val

    return None


# =========================
# MAIN EXPORT
# =========================
def main():
    print("\n========================================")
    print("   GAZE / VIDEO SYNCHRONIZATION")
    print("========================================\n")

    # -------------------------
    # FILE SELECTION
    # -------------------------
    print("[STEP 1] Selecting files...")
    mp4_path = select_file("Select MP4", [("MP4", "*.mp4")])
    if not mp4_path:
        print("ERROR: No MP4 selected. Exiting.")
        return
    xdf_path = select_file("Select XDF", [("XDF", "*.xdf")])
    if not xdf_path:
        print("ERROR: No XDF selected. Exiting.")
        return
    print("\nFile selection complete.\n")

    # -------------------------
    # LOAD XDF
    # -------------------------
    print("[STEP 2] Loading XDF...")
    streams = load_xdf(xdf_path)

    # -------------------------
    # FIND STREAMS
    # -------------------------
    print("\n[STEP 3] Finding required streams...")
    event_streams = get_stream(streams, "EyeTracker Device_Neon Events")
    gaze_streams = get_stream(streams, "EyeTracker Device_Neon Gaze")
    if len(event_streams) == 0:
        print("ERROR: Event stream not found.")
        return
    if len(gaze_streams) == 0:
        print("ERROR: Gaze stream not found.")
        return
    event_stream = event_streams[0]
    gaze_stream = gaze_streams[0]
    print("      Event stream OK.")
    print("      Gaze stream OK.")

    # -------------------------
    # PARSE EVENTS
    # -------------------------
    print("\n[STEP 4] Parsing data...")
    events = parse_events(event_stream)
    gaze_t, gx, gy = parse_gaze(gaze_stream)
    if len(events) == 0:
        print("ERROR: No events found.")
        return
    if len(gaze_t) == 0:
        print("ERROR: No gaze data found.")
        return

    raw_gaze_t = np.copy(gaze_t)

    # -------------------------
    # OUTPUT FOLDER PREPARATION
    # -------------------------
    print("\n[STEP 5] Preparing output folder...")
    out_dir = r"C:\Users\fhoffmann\Desktop\eye_segments"
    os.makedirs(out_dir, exist_ok=True)
    print(f"      Output folder: {out_dir}")
    print("      Output folder ready.")

    # -------------------------
    # ALIGN TIMEBASE
    # -------------------------
    print("\n[STEP 6] Aligning timebases...")
    start_time = events[0][0]
    print(f"      Reference start time: {start_time:.6f}")
    events = [(t - start_time, m) for t, m in events]
    gaze_t = gaze_t - start_time
    print(
        f"      Event time range: "
        f"{events[0][0]:.3f} → {events[-1][0]:.3f} sec"
    )
    print(f"      Gaze time range: " f"{gaze_t[0]:.3f} → {gaze_t[-1]:.3f} sec")
    if len(events) >= 2:
        print(
            f"      First two events: "
            f"{events[0][0]:.3f}, {events[1][0]:.3f}"
        )
    print("      Timebase alignment complete.")

    # -------------------------
    # EXPORT CALIBRATION GAZE TO XLSX
    # -------------------------
    export_calibration_gaze(events, gaze_t, gx, gy, raw_gaze_t, out_dir)

    # -------------------------
    # VIDEO
    # -------------------------
    print("\n[STEP 7] Opening video...")
    cap = cv2.VideoCapture(mp4_path)
    if not cap.isOpened():
        print("ERROR: Could not open video.")
        return
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = frame_count / fps if fps > 0 else 0
    print(f"      FPS:          {fps:.2f}")
    print(f"      Resolution:   {width} x {height}")
    print(f"      Frame count:  {frame_count}")
    print(f"      Duration:     {duration:.2f} sec")

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")

    # -------------------------
    # BUILD SEGMENTS
    # -------------------------
    print("\n[STEP 8] Building fight segments...")
    FIGHT_PAD = 0
    fight_events = [
        (t, m)
        for t, m in events
        if "Fight" in m
        or "recording.begin" in m
        or "Neon_calibration_start" in m
        or "Neon_calibration_stop" in m
    ]
    print(f"      Fight events found: {len(fight_events)}")
    segments = []
    for i in range(len(fight_events) - 1):
        t0, m0 = fight_events[i]
        t1, _ = fight_events[i + 1]
        start = max(0, t0 - FIGHT_PAD)
        end = t1 - FIGHT_PAD
        segments.append((start, end, m0))
        print(
            f"      Segment {i:03d}: "
            f"{start:.3f} → {end:.3f} sec | "
            f"{m0}"
        )
    print(f"\n      Total segments: {len(segments)}")
    if len(segments) == 0:
        print("ERROR: No segments created.")
        cap.release()
        return

    # -------------------------
    # PROCESS EACH SEGMENT
    # -------------------------
    print("\n========================================")
    print("STARTING VIDEO EXPORT")
    print("========================================\n")
    for idx, (t0, t1, label) in enumerate(segments):
        print(f"\n[SEGMENT {idx + 1}/{len(segments)}]")
        print(f"      Label: {label}")
        print(f"      Start: {t0:.3f} sec")
        print(f"      End:   {t1:.3f} sec")
        print(f"      Duration: {t1 - t0:.3f} sec")

        print("      Seeking video...")
        cap.set(cv2.CAP_PROP_POS_MSEC, t0 * 1000)
        actual_start = cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0
        print(f"      Actual video position: {actual_start:.3f} sec")

        safe_label = str(label).replace(os.sep, "_")
        out_path = os.path.join(out_dir, f"{idx:03d}_{safe_label}.mp4")
        print(f"      Creating output: {out_path}")
        writer = cv2.VideoWriter(out_path, fourcc, fps, (width, height))
        if not writer.isOpened():
            print("      ERROR: Could not create video writer.")
            continue

        frame_number = 0
        gaze_count = 0
        expected_frames = int((t1 - t0) * fps)
        print(f"      Expected frames: {expected_frames}")
        last_report = -1

        while True:
            # 1. READ FRAME FIRST
            ret, frame = cap.read()
            if not ret:
                print("      Reached video end or cannot read next frame.")
                break

            # 2. CALCULATE TIME BASED ON FRAME INDEX
            current_t = t0 + (frame_number / fps)
            if current_t > t1:
                print(
                    f"      Reached segment end timestamp ({current_t:.3f} sec)."
                )
                break

            # 3. GET NEAREST RECORDED GAZE SAMPLE (Tolerance = half of frame duration)
            gaze_raw = get_nearest_gaze(
                current_t, gaze_t, gx, gy, max_dt=(1.0 / (2 * fps))
            )

            if gaze_raw is not None:
                gx_val, gy_val = gaze_raw

                # Scale normalized coordinates (0.0 to 1.0) to pixel resolution
                if 0.0 <= gx_val <= 1.0 and 0.0 <= gy_val <= 1.0:
                    pixel_x = int(gx_val * width)
                    pixel_y = int(gy_val * height)
                else:
                    pixel_x = int(gx_val)
                    pixel_y = int(gy_val)

                gaze_count += 1
                cv2.circle(frame, (pixel_x, pixel_y), 8, (0, 0, 255), -1)

            # 4. OVERLAY LABEL & WRITE FRAME
            cv2.putText(
                frame,
                label,
                (30, 60),
                cv2.FONT_HERSHEY_SIMPLEX,
                1,
                (0, 255, 255),
                2,
            )
            writer.write(frame)

            frame_number += 1

            # 5. PROGRESS REPORTING
            if expected_frames > 0:
                progress = int(frame_number / expected_frames * 100)
                report = progress // 10
                if report > last_report:
                    print(
                        f"      Progress: {min(progress, 100):3d}% "
                        f"({frame_number} frames, {current_t:.2f} sec)"
                    )
                    last_report = report

        writer.release()
        print("      Segment finished.")
        print(f"      Frames written: {frame_number}")
        print(f"      Frames with matched gaze: {gaze_count}")
        if frame_number > 0:
            gaze_percentage = gaze_count / frame_number * 100
            print(f"      Gaze coverage: {gaze_percentage:.1f}%")
        print(f"      Saved to: {out_path}")

    print("\nCleaning up...")
    cap.release()
    print("Video released.")
    print("\n========================================")
    print("DONE")
    print("========================================")
    print(f"Segments exported: {len(segments)}")
    print(f"Output folder: {out_dir}")


if __name__ == "__main__":
    main()