##Saving

import os
import re
from pathlib import Path
import tkinter as tk
from tkinter import filedialog

import cv2
import numpy as np
import pandas as pd
import pyxdf

from pupil_labs import neon_recording as nr
from pupil_labs.video import Writer


# ============================================================
# SETTINGS
# ============================================================

EVENT_STREAM_NAME = "EyeTracker Device_Neon Events"

# Fight segments:
# Fight1 - 4.5 sec -> Fight2 - 4.5 sec
# Fight2 - 4.5 sec -> Fight3 - 4.5 sec
FIGHT_PRE_TIME = 4.5

# Main folder created inside the user-selected output folder
SYNC_FOLDER_NAME = "syncdata"

# Final BIDS eyetracking folder
EYE_TRACKING_FOLDER_NAME = "eyetracking"

# Overlay settings
GAZE_RADIUS = 8
GAZE_THICKNESS = 2

FIXATION_RADIUS = 20
FIXATION_THICKNESS = -1

# Smoothing of gaze position for video overlay only
GAZE_SMOOTHING_WINDOW = 5


# ============================================================
# GUI
# ============================================================

def select_inputs_and_output():

    print("[1/3] Opening Neon recording folder selector...")

    root = tk.Tk()
    root.withdraw()

    # Keep dialogs in front on Windows
    root.attributes("-topmost", True)
    root.update()

    # --------------------------------------------------------
    # Neon recording folder
    # --------------------------------------------------------

    neon_path = filedialog.askdirectory(
        parent=root,
        title="1. Select Neon recording folder"
    )

    if not neon_path:
        root.destroy()
        raise SystemExit(
            "No Neon recording folder selected."
        )

    print(f"      Neon folder: {neon_path}")

    # --------------------------------------------------------
    # XDF file
    # --------------------------------------------------------

    print("[2/3] Opening XDF file selector...")

    xdf_path = filedialog.askopenfilename(
        parent=root,
        title="2. Select XDF file",
        filetypes=[
            ("XDF files", "*.xdf"),
            ("All files", "*.*")
        ]
    )

    if not xdf_path:
        root.destroy()
        raise SystemExit(
            "No XDF file selected."
        )

    print(f"      XDF file: {xdf_path}")

    # --------------------------------------------------------
    # Parent output folder
    # --------------------------------------------------------

    print("[3/3] Opening output folder selector...")

    output_parent = filedialog.askdirectory(
        parent=root,
        title="3. Select parent output folder"
    )

    if not output_parent:
        root.destroy()
        raise SystemExit(
            "No output folder selected."
        )

    print(
        f"      Parent output folder: "
        f"{output_parent}"
    )

    root.destroy()

    return neon_path, xdf_path, output_parent


# ============================================================
# BIDS NAME PARSING
# ============================================================

def parse_neon_folder_name(neon_path):

    """
    Expected Neon folder name:

    sub-XXXXXX_ses-S001_task-heightaffordance_run-00X_eyetracking

    Example:

    sub-000123_ses-S001_task-heightaffordance_run-001_eyetracking
    """

    folder_name = Path(neon_path).name

    print("\nParsing BIDS information from Neon folder:")
    print(f"  {folder_name}")

    # --------------------------------------------------------
    # Subject
    # --------------------------------------------------------

    subject_match = re.search(
        r"(sub-[^_]+)",
        folder_name
    )

    # --------------------------------------------------------
    # Session
    # --------------------------------------------------------

    session_match = re.search(
        r"(ses-[^_]+)",
        folder_name
    )

    # --------------------------------------------------------
    # Task
    # --------------------------------------------------------

    task_match = re.search(
        r"(task-[^_]+)",
        folder_name
    )

    # --------------------------------------------------------
    # Run
    # --------------------------------------------------------

    run_match = re.search(
        r"(run-[^_]+)",
        folder_name
    )

    if subject_match is None:

        raise RuntimeError(
            "Could not find subject ID in Neon folder name.\n"
            "Expected something like:\n"
            "sub-XXXXXX_ses-S001_task-heightaffordance_run-001_eyetracking"
        )

    if session_match is None:

        raise RuntimeError(
            "Could not find session ID in Neon folder name."
        )

    if task_match is None:

        raise RuntimeError(
            "Could not find task name in Neon folder name."
        )

    if run_match is None:

        raise RuntimeError(
            "Could not find run number in Neon folder name."
        )

    subject = subject_match.group(1)
    session = session_match.group(1)
    task = task_match.group(1)
    run = run_match.group(1)

    # --------------------------------------------------------
    # Full BIDS stem
    # --------------------------------------------------------

    bids_stem = (
        f"{subject}_"
        f"{session}_"
        f"{task}_"
        f"{run}"
    )

    print("\nBIDS information:")
    print(f"  Subject: {subject}")
    print(f"  Session: {session}")
    print(f"  Task:    {task}")
    print(f"  Run:     {run}")
    print(f"  Stem:    {bids_stem}")

    return {
        "subject": subject,
        "session": session,
        "task": task,
        "run": run,
        "stem": bids_stem
    }


# ============================================================
# OUTPUT DIRECTORY
# ============================================================

def create_output_directory(
    output_parent,
    bids_info
):

    """
    Creates:

    [chosen folder]/
        syncdata/
            sub-XXXXXX/
                ses-S001/
                    eyetracking/
    """

    print(
        "\nChecking / creating BIDS output directory..."
    )

    output_parent = Path(
        output_parent
    )

    syncdata_dir = (
        output_parent
        / SYNC_FOLDER_NAME
    )

    subject_dir = (
        syncdata_dir
        / bids_info["subject"]
    )

    session_dir = (
        subject_dir
        / bids_info["session"]
    )

    eyetracking_dir = (
        session_dir
        / EYE_TRACKING_FOLDER_NAME
    )

    # --------------------------------------------------------
    # Create hierarchy
    # --------------------------------------------------------

    if syncdata_dir.exists():

        print(
            f"  Found: {syncdata_dir}"
        )

    else:

        print(
            f"  Creating: {syncdata_dir}"
        )

        syncdata_dir.mkdir(
            parents=True,
            exist_ok=True
        )

    if subject_dir.exists():

        print(
            f"  Found: {subject_dir}"
        )

    else:

        print(
            f"  Creating: {subject_dir}"
        )

        subject_dir.mkdir(
            parents=True,
            exist_ok=True
        )

    if session_dir.exists():

        print(
            f"  Found: {session_dir}"
        )

    else:

        print(
            f"  Creating: {session_dir}"
        )

        session_dir.mkdir(
            parents=True,
            exist_ok=True
        )

    if eyetracking_dir.exists():

        print(
            f"  Found: {eyetracking_dir}"
        )

    else:

        print(
            f"  Creating: {eyetracking_dir}"
        )

        eyetracking_dir.mkdir(
            parents=True,
            exist_ok=True
        )

    print(
        "\nFinal output directory:"
    )

    print(
        f"  {eyetracking_dir}"
    )

    return eyetracking_dir


# ============================================================
# XDF
# ============================================================

def load_xdf(path):

    print("\nLoading XDF...")

    streams, _ = pyxdf.load_xdf(path)

    print(
        f"XDF streams found: {len(streams)}"
    )

    for i, stream in enumerate(streams):

        name = stream["info"]["name"][0]

        try:

            n_samples = len(
                stream["time_stamps"]
            )

        except Exception:

            n_samples = "?"

        print(
            f"  Stream {i}: "
            f"{name} "
            f"({n_samples} samples)"
        )

    return streams


def get_event_stream(streams):

    print(
        "\nSearching for event stream..."
    )

    # Exact name first
    for stream in streams:

        name = stream["info"]["name"][0]

        if name == EVENT_STREAM_NAME:

            print(
                f"Found event stream: {name}"
            )

            return stream

    # Fallback
    print(
        "Exact event stream not found."
    )

    print(
        "Searching for streams containing 'Event'..."
    )

    for stream in streams:

        name = stream["info"]["name"][0]

        if "event" in name.lower():

            print(
                f"Using event stream: {name}"
            )

            return stream

    raise RuntimeError(
        "Could not find an XDF event stream."
    )


def parse_events(event_stream):

    print(
        "\nParsing XDF event markers..."
    )

    timestamps = np.asarray(
        event_stream["time_stamps"],
        dtype=float
    )

    raw_markers = (
        event_stream["time_series"]
    )

    markers = []

    for item in raw_markers:

        if isinstance(item, list):

            if len(item) > 0:

                markers.append(
                    str(item[0])
                )

            else:

                markers.append("")

        else:

            markers.append(
                str(item)
            )

    events = []

    for timestamp, marker in zip(
        timestamps,
        markers,
        strict=False
    ):

        events.append(
            {
                "xdf_timestamp": float(timestamp),
                "marker": marker
            }
        )

    print(
        f"Event markers found: "
        f"{len(events)}"
    )

    print(
        "\nEvent markers:"
    )

    for event in events:

        print(
            f"  "
            f"{event['xdf_timestamp']:.3f} sec    "
            f"{event['marker']}"
        )

    return events


# ============================================================
# SYNCHRONIZATION
# ============================================================

def synchronize_events(
    events,
    recording
):

    print(
        "\nSynchronizing XDF events with Neon..."
    )

    recording_begin = None

    for event in events:

        if event["marker"] == "recording.begin":

            recording_begin = (
                event["xdf_timestamp"]
            )

            break

    if recording_begin is None:

        raise RuntimeError(
            "Could not find 'recording.begin' "
            "in XDF events."
        )

    print(
        f"XDF recording.begin: "
        f"{recording_begin:.6f} sec"
    )

    print(
        f"Neon recording.start_time: "
        f"{recording.start_time}"
    )

    synchronized = []

    for event in events:

        # Relative to XDF recording.begin
        relative_time = (
            event["xdf_timestamp"]
            - recording_begin
        )

        # Convert to native Neon nanoseconds
        neon_timestamp = (
            recording.start_time
            + int(
                round(
                    relative_time * 1e9
                )
            )
        )

        synchronized.append(
            {
                "marker": event["marker"],

                "xdf_timestamp": (
                    event["xdf_timestamp"]
                ),

                "relative_time_sec": (
                    relative_time
                ),

                "neon_timestamp_ns": (
                    neon_timestamp
                )
            }
        )

    print(
        "\nSynchronized events:"
    )

    for event in synchronized:

        print(
            f"  "
            f"{event['relative_time_sec']:10.3f} sec   "
            f"{event['neon_timestamp_ns']}   "
            f"{event['marker']}"
        )

    return synchronized


# ============================================================
# RANGED INDEX
# ============================================================

def find_ranged_index(
    values,
    left_boundaries,
    right_boundaries
):

    values = np.asarray(
        values
    )

    left_boundaries = np.asarray(
        left_boundaries
    )

    right_boundaries = np.asarray(
        right_boundaries
    )

    left_ids = np.searchsorted(
        left_boundaries,
        values,
        side="right"
    ) - 1

    right_ids = np.searchsorted(
        right_boundaries,
        values,
        side="right"
    )

    return np.where(
        left_ids == right_ids,
        left_ids,
        -1
    )


# ============================================================
# FIXATION LOOKUP
# ============================================================

def build_fixation_lookup(recording):

    print(
        "\nBuilding fixation lookup..."
    )

    fixations = recording.fixations

    starts = np.asarray(
        fixations.start_time,
        dtype=np.int64
    )

    stops = np.asarray(
        fixations.stop_time,
        dtype=np.int64
    )

    mean_points = np.asarray(
        fixations.mean_gaze_point,
        dtype=float
    )

    lookup = []

    for i in range(
        len(starts)
    ):

        lookup.append(
            {
                "id": i + 1,

                "start": starts[i],

                "stop": stops[i],

                "x": mean_points[i][0],

                "y": mean_points[i][1]
            }
        )

    print(
        f"Fixations available: "
        f"{len(lookup)}"
    )

    return lookup


def get_fixation_at_time(
    timestamp,
    fixation_lookup
):

    for fixation in fixation_lookup:

        if (
            fixation["start"]
            <= timestamp
            <= fixation["stop"]
        ):

            return fixation

    return None


# ============================================================
# GAZE DATAFRAME
# ============================================================

def build_gaze_dataframe(
    recording,
    synchronized_events
):

    print(
        "\nBuilding native Neon gaze dataframe..."
    )

    gaze_time = np.asarray(
        recording.gaze.time,
        dtype=np.int64
    )

    gaze_points = np.asarray(
        recording.gaze.point,
        dtype=float
    )

    n = len(gaze_time)

    print(
        f"Neon gaze samples: {n}"
    )

    # --------------------------------------------------------
    # Fixation IDs
    # --------------------------------------------------------

    fixations = recording.fixations

    fixation_ids = (
        find_ranged_index(
            gaze_time,
            fixations.start_time,
            fixations.stop_time
        )
        + 1
    )

    fixation_ids = np.where(
        fixation_ids > 0,
        fixation_ids,
        0
    )

    # --------------------------------------------------------
    # Blink IDs
    # --------------------------------------------------------

    blinks = recording.blinks

    blink_ids = (
        find_ranged_index(
            gaze_time,
            blinks.start_time,
            blinks.stop_time
        )
        + 1
    )

    blink_ids = np.where(
        blink_ids > 0,
        blink_ids,
        0
    )

    # --------------------------------------------------------
    # Worn
    # --------------------------------------------------------

    worn = np.asarray(
        recording.worn.worn
    )

    if len(worn) != n:

        print(
            "Warning: worn array length differs "
            "from gaze length."
        )

        worn_values = np.full(
            n,
            np.nan
        )

        length = min(
            n,
            len(worn)
        )

        worn_values[:length] = (
            worn[:length]
        )

        worn = worn_values

    # --------------------------------------------------------
    # DataFrame
    # --------------------------------------------------------

    df = pd.DataFrame(
        {
            "timestamp_ns": gaze_time,

            "relative_time_sec": (
                gaze_time
                - recording.start_time
            ) / 1e9,

            "gaze_x_px": gaze_points[:, 0],

            "gaze_y_px": gaze_points[:, 1],

            "worn": worn,

            "fixation_id": fixation_ids,

            "blink_id": blink_ids
        }
    )

    # --------------------------------------------------------
    # Nearest marker
    # --------------------------------------------------------

    if synchronized_events:

        event_times = np.asarray(
            [
                e["neon_timestamp_ns"]
                for e in synchronized_events
            ],
            dtype=np.int64
        )

        event_names = [
            e["marker"]
            for e in synchronized_events
        ]

        event_indices = np.searchsorted(
            event_times,
            gaze_time
        )

        previous_indices = np.clip(
            event_indices - 1,
            0,
            len(event_times) - 1
        )

        next_indices = np.clip(
            event_indices,
            0,
            len(event_times) - 1
        )

        previous_distance = np.abs(
            gaze_time
            - event_times[
                previous_indices
            ]
        )

        next_distance = np.abs(
            gaze_time
            - event_times[
                next_indices
            ]
        )

        nearest_indices = np.where(
            previous_distance
            <= next_distance,
            previous_indices,
            next_indices
        )

        df["nearest_marker"] = [
            event_names[i]
            for i in nearest_indices
        ]

        df[
            "nearest_marker_timestamp_ns"
        ] = [
            event_times[i]
            for i in nearest_indices
        ]

    return df


# ============================================================
# SEGMENTS
# ============================================================

def build_segments(
    synchronized_events,
    recording
):

    print(
        "\nBuilding video segments..."
    )

    # IMPORTANT:
    # recording.duration is already an integer
    # in nanoseconds.

    recording_start = (
        recording.start_time
    )

    recording_end = (
        recording.start_time
        + recording.duration
    )

    print(
        f"Recording start: "
        f"{recording_start}"
    )

    print(
        f"Recording duration: "
        f"{recording.duration} ns"
    )

    print(
        f"Recording end: "
        f"{recording_end}"
    )

    calibration_start = None
    calibration_stop = None

    fights = []

    # --------------------------------------------------------
    # Find markers
    # --------------------------------------------------------

    for event in synchronized_events:

        marker = event["marker"]

        timestamp = (
            event["neon_timestamp_ns"]
        )

        if marker == "Neon_calibration_start":

            calibration_start = timestamp

        elif marker == "Neon_calibration_stop":

            calibration_stop = timestamp

        elif marker.startswith("Fight"):

            fights.append(
                {
                    "marker": marker,
                    "timestamp": timestamp
                }
            )

    segments = []

    # ========================================================
    # CALIBRATION
    # ========================================================

    if (
        calibration_start is not None
        and calibration_stop is not None
    ):

        segments.append(
            {
                "start": calibration_start,

                "end": calibration_stop,

                "label": "Neon_calibration",

                "type": "calibration"
            }
        )

        print(
            "\nCalibration segment:"
        )

        print(
            f"  "
            f"{(calibration_start - recording_start) / 1e9:.3f}"
            f" -> "
            f"{(calibration_stop - recording_start) / 1e9:.3f}"
            f" sec"
        )

    else:

        print(
            "\nWARNING: Calibration start/stop "
            "markers not both found."
        )

    # ========================================================
    # FIGHTS
    # ========================================================

    fights.sort(
        key=lambda x: x["timestamp"]
    )

    print(
        f"\nFight markers found: "
        f"{len(fights)}"
    )

    for i, fight in enumerate(
        fights
    ):

        # Start 4.5 sec before Fight marker
        start = (
            fight["timestamp"]
            - int(
                FIGHT_PRE_TIME * 1e9
            )
        )

        # End 4.5 sec before next Fight
        if i + 1 < len(fights):

            next_fight = (
                fights[i + 1]
            )

            end = (
                next_fight["timestamp"]
                - int(
                    FIGHT_PRE_TIME * 1e9
                )
            )

        else:

            # Last fight goes to recording end
            end = recording_end

            print(
                f"\nWARNING: "
                f"{fight['marker']} is the last "
                f"fight marker."
            )

            print(
                "Using recording end as "
                "segment end."
            )

        # ----------------------------------------------------
        # Clamp to recording
        # ----------------------------------------------------

        if start < recording_start:

            start = recording_start

        if end > recording_end:

            end = recording_end

        # ----------------------------------------------------
        # Validate
        # ----------------------------------------------------

        if end <= start:

            print(
                f"Skipping invalid segment: "
                f"{fight['marker']}"
            )

            continue

        segments.append(
            {
                "start": start,

                "end": end,

                "label": fight["marker"],

                "type": "fight"
            }
        )

        print(
            f"\n{fight['marker']}:"
        )

        print(
            f"  Start: "
            f"{(start - recording_start) / 1e9:.3f} sec"
        )

        print(
            f"  End:   "
            f"{(end - recording_start) / 1e9:.3f} sec"
        )

        print(
            f"  Duration: "
            f"{(end - start) / 1e9:.3f} sec"
        )

    # ========================================================
    # SORT
    # ========================================================

    segments.sort(
        key=lambda x: x["start"]
    )

    print(
        f"\nTotal segments: "
        f"{len(segments)}"
    )

    return segments


# ============================================================
# GAZE SMOOTHING
# ============================================================

def smooth_gaze_positions(
    x,
    y,
    window_size=5
):

    x = np.asarray(
        x,
        dtype=float
    )

    y = np.asarray(
        y,
        dtype=float
    )

    valid = (
        np.isfinite(x)
        & np.isfinite(y)
    )

    smoothed_x = x.copy()
    smoothed_y = y.copy()

    if not np.any(valid):

        return (
            smoothed_x,
            smoothed_y
        )

    indices = np.arange(
        len(x)
    )

    valid_indices = indices[
        valid
    ]

    # Interpolate missing gaze
    smoothed_x[~valid] = np.interp(
        indices[~valid],
        valid_indices,
        x[valid]
    )

    smoothed_y[~valid] = np.interp(
        indices[~valid],
        valid_indices,
        y[valid]
    )

    # Moving average
    kernel = (
        np.ones(window_size)
        / window_size
    )

    smoothed_x = np.convolve(
        smoothed_x,
        kernel,
        mode="same"
    )

    smoothed_y = np.convolve(
        smoothed_y,
        kernel,
        mode="same"
    )

    return (
        smoothed_x,
        smoothed_y
    )


# ============================================================
# SAFE BIDS LABEL
# ============================================================

def bids_safe_label(label):

    """
    Convert a marker into a BIDS-compatible-ish label.

    Example:

    Neon_calibration -> NeonCalibration
    Fight1          -> Fight1
    """

    label = str(label)

    # Remove underscores
    label = label.replace(
        "_",
        ""
    )

    # Remove anything unusual
    label = re.sub(
        r"[^A-Za-z0-9]+",
        "",
        label
    )

    return label


# ============================================================
# VIDEO CREATION
# ============================================================

def create_segment_video(
    recording,
    segment,
    output_path,
    fixation_lookup
):

    print(
        f"\nCreating: "
        f"{output_path.name}"
    )

    start = segment["start"]
    end = segment["end"]

    print(
        f"Time: "
        f"{(start - recording.start_time) / 1e9:.3f}"
        f" -> "
        f"{(end - recording.start_time) / 1e9:.3f} sec"
    )

    # --------------------------------------------------------
    # Scene timestamps
    # --------------------------------------------------------

    scene_times = np.asarray(
        recording.scene.time,
        dtype=np.int64
    )

    mask = (
        (scene_times >= start)
        & (scene_times <= end)
    )

    segment_scene_times = (
        scene_times[mask]
    )

    print(
        f"Scene frames: "
        f"{len(segment_scene_times)}"
    )

    if len(segment_scene_times) == 0:

        print(
            "No scene frames in this segment."
        )

        return

    # --------------------------------------------------------
    # Sample gaze
    # --------------------------------------------------------

    print(
        "Sampling Neon gaze at "
        "scene timestamps..."
    )

    sampled_gaze = (
        recording.gaze.sample(
            segment_scene_times
        )
    )

    # --------------------------------------------------------
    # Sample scene
    # --------------------------------------------------------

    print(
        "Sampling Neon scene frames..."
    )

    scene_frames = (
        recording.scene.sample(
            segment_scene_times
        )
    )

    # --------------------------------------------------------
    # Extract gaze
    # --------------------------------------------------------

    gaze_x = np.full(
        len(segment_scene_times),
        np.nan
    )

    gaze_y = np.full(
        len(segment_scene_times),
        np.nan
    )

    for i, gaze in enumerate(
        sampled_gaze
    ):

        if gaze is None:
            continue

        try:

            point = gaze.point

            if point is not None:

                gaze_x[i] = float(
                    point[0]
                )

                gaze_y[i] = float(
                    point[1]
                )

        except Exception:
            pass

    # --------------------------------------------------------
    # Smooth gaze
    # --------------------------------------------------------

    smooth_x, smooth_y = (
        smooth_gaze_positions(
            gaze_x,
            gaze_y,
            GAZE_SMOOTHING_WINDOW
        )
    )

    # --------------------------------------------------------
    # Writer
    # --------------------------------------------------------

    print(
        "Opening video writer..."
    )

    writer = Writer(
        str(output_path)
    )

    frames_written = 0
    frames_with_fixation = 0

    # ========================================================
    # WRITE FRAMES
    # ========================================================

    for i, (
        scene_frame,
        timestamp
    ) in enumerate(
        zip(
            scene_frames,
            segment_scene_times,
            strict=True
        )
    ):

        frame = scene_frame.bgr

        if frame is None:
            continue

        frame = frame.copy()

        # ====================================================
        # RED = SMOOTHED GAZE
        # ====================================================

        if (
            np.isfinite(
                smooth_x[i]
            )
            and
            np.isfinite(
                smooth_y[i]
            )
        ):

            gx = int(
                round(
                    smooth_x[i]
                )
            )

            gy = int(
                round(
                    smooth_y[i]
                )
            )

            cv2.circle(
                frame,
                (gx, gy),
                GAZE_RADIUS,
                (0, 0, 255),
                GAZE_THICKNESS,
                cv2.LINE_AA
            )

        # ====================================================
        # YELLOW = ACTIVE FIXATION
        # ====================================================

        fixation = (
            get_fixation_at_time(
                timestamp,
                fixation_lookup
            )
        )

        if fixation is not None:

            frames_with_fixation += 1

            fx = int(
                round(
                    fixation["x"]
                )
            )

            fy = int(
                round(
                    fixation["y"]
                )
            )

            # Filled yellow circle
            cv2.circle(
                frame,
                (fx, fy),
                FIXATION_RADIUS,
                (0, 255, 255),
                FIXATION_THICKNESS,
                cv2.LINE_AA
            )

            # Outline
            cv2.circle(
                frame,
                (fx, fy),
                FIXATION_RADIUS + 3,
                (0, 255, 255),
                2,
                cv2.LINE_AA
            )

            # Fixation ID
            cv2.putText(
                frame,
                f"Fixation {fixation['id']}",
                (
                    fx + FIXATION_RADIUS + 8,
                    fy
                ),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (0, 255, 255),
                1,
                cv2.LINE_AA
            )

        # ====================================================
        # WRITE FRAME
        # ====================================================

        video_time = (
            timestamp
            - segment_scene_times[0]
        ) / 1e9

        writer.write_image(
            frame,
            time=float(
                video_time
            )
        )

        frames_written += 1

    # --------------------------------------------------------
    # Close writer
    # --------------------------------------------------------

    writer.close()

    print(
        f"Frames written: "
        f"{frames_written}"
    )

    print(
        f"Frames containing fixation: "
        f"{frames_with_fixation}"
    )

    if frames_written > 0:

        coverage = (
            frames_with_fixation
            / frames_written
            * 100
        )

        print(
            f"Fixation coverage: "
            f"{coverage:.1f}%"
        )


# ============================================================
# SAVE EVENTS
# ============================================================

def save_events(
    synchronized_events,
    output_dir,
    bids_info
):

    """
    Save synchronized events as BIDS-style TSV.
    """

    filename = (
        f"{bids_info['stem']}"
        f"_events.tsv"
    )

    output_path = (
        output_dir
        / filename
    )

    df = pd.DataFrame(
        synchronized_events
    )

    # Add BIDS-style onset
    if len(df) > 0:

        first_time = (
            df["neon_timestamp_ns"].iloc[0]
        )

        df["onset"] = (
            df["neon_timestamp_ns"]
            - first_time
        ) / 1e9

    df.to_csv(
        output_path,
        sep="\t",
        index=False
    )

    print(
        "\nSaved BIDS events file:"
    )

    print(
        f"  {output_path}"
    )

    return output_path


# ============================================================
# SAVE GAZE
# ============================================================

def save_gaze(
    gaze_df,
    output_dir,
    bids_info
):

    """
    Save native Neon gaze as a BIDS-style CSV.

    The filename contains:

    sub
    ses
    task
    run
    desc
    eyetracking
    """

    filename = (
        f"{bids_info['stem']}"
        f"_desc-NeonGaze"
        f"_eyetracking.csv"
    )

    output_path = (
        output_dir
        / filename
    )

    gaze_df.to_csv(
        output_path,
        index=False
    )

    print(
        "\nSaved BIDS gaze file:"
    )

    print(
        f"  {output_path}"
    )

    return output_path


# ============================================================
# MAIN
# ============================================================

def main():

    print("=" * 70)
    print(
        "NEON + XDF BIDS SYNCHRONIZATION"
    )
    print("=" * 70)

    # ========================================================
    # GUI
    # ========================================================

    neon_path, xdf_path, output_parent = (
        select_inputs_and_output()
    )

    # ========================================================
    # PARSE BIDS NAME
    # ========================================================

    bids_info = parse_neon_folder_name(
        neon_path
    )

    # ========================================================
    # CREATE OUTPUT STRUCTURE
    # ========================================================

    output_dir = (
        create_output_directory(
            output_parent,
            bids_info
        )
    )

    # ========================================================
    # OPEN NEON
    # ========================================================

    print("\n" + "=" * 70)
    print(
        "OPENING NEON RECORDING"
    )
    print("=" * 70)

    recording = nr.open(
        neon_path
    )

    print(
        f"Recording start time: "
        f"{recording.start_time}"
    )

    print(
        f"Recording duration: "
        f"{recording.duration} ns"
    )

    # ========================================================
    # SCENE INFO
    # ========================================================

    try:

        scene_times = np.asarray(
            recording.scene.time
        )

        print(
            f"Scene frames: "
            f"{len(scene_times)}"
        )

        if len(scene_times) > 1:

            scene_fps = (
                1e9
                / np.median(
                    np.diff(scene_times)
                )
            )

            print(
                f"Scene FPS: "
                f"{scene_fps:.2f}"
            )

    except Exception as e:

        print(
            f"Could not determine "
            f"scene FPS: {e}"
        )

    # ========================================================
    # GAZE INFO
    # ========================================================

    try:

        gaze_times = np.asarray(
            recording.gaze.time
        )

        print(
            f"Gaze samples: "
            f"{len(gaze_times)}"
        )

        if len(gaze_times) > 1:

            gaze_rate = (
                1e9
                / np.median(
                    np.diff(gaze_times)
                )
            )

            print(
                f"Gaze sampling rate: "
                f"{gaze_rate:.2f} Hz"
            )

    except Exception as e:

        print(
            f"Could not determine "
            f"gaze rate: {e}"
        )

    # ========================================================
    # FIXATIONS
    # ========================================================

    try:

        print(
            f"Fixations: "
            f"{len(recording.fixations.start_time)}"
        )

    except Exception:
        pass

    # ========================================================
    # BLINKS
    # ========================================================

    try:

        print(
            f"Blinks: "
            f"{len(recording.blinks.start_time)}"
        )

    except Exception:
        pass

    # ========================================================
    # LOAD XDF
    # ========================================================

    print("\n" + "=" * 70)
    print(
        "LOADING XDF"
    )
    print("=" * 70)

    streams = load_xdf(
        xdf_path
    )

    event_stream = (
        get_event_stream(
            streams
        )
    )

    events = parse_events(
        event_stream
    )

    # ========================================================
    # SYNCHRONIZE
    # ========================================================

    synchronized_events = (
        synchronize_events(
            events,
            recording
        )
    )

    # ========================================================
    # SAVE EVENTS
    # ========================================================

    save_events(
        synchronized_events,
        output_dir,
        bids_info
    )

    # ========================================================
    # BUILD GAZE
    # ========================================================

    gaze_df = (
        build_gaze_dataframe(
            recording,
            synchronized_events
        )
    )

    # ========================================================
    # SAVE GAZE
    # ========================================================

    save_gaze(
        gaze_df,
        output_dir,
        bids_info
    )

    # ========================================================
    # BUILD SEGMENTS
    # ========================================================

    segments = (
        build_segments(
            synchronized_events,
            recording
        )
    )

    # ========================================================
    # FIXATION LOOKUP
    # ========================================================

    fixation_lookup = (
        build_fixation_lookup(
            recording
        )
    )

    # ========================================================
    # CREATE VIDEOS
    # ========================================================

    print("\n" + "=" * 70)
    print(
        "CREATING VIDEO SEGMENTS"
    )
    print("=" * 70)

    for index, segment in enumerate(
        segments
    ):

        segment_label = bids_safe_label(
            segment["label"]
        )

        filename = (
            f"{bids_info['stem']}"
            f"_desc-{segment_label}"
            f"_eyetracking.mp4"
        )

        output_video = (
            output_dir
            / filename
        )

        try:

            create_segment_video(
                recording,
                segment,
                output_video,
                fixation_lookup
            )

        except Exception as e:

            print(
                f"\nERROR creating "
                f"{filename}:"
            )

            print(
                repr(e)
            )

    # ========================================================
    # DONE
    # ========================================================

    print("\n" + "=" * 70)
    print(
        "DONE"
    )
    print("=" * 70)

    print(
        "\nBIDS subject:"
    )

    print(
        f"  {bids_info['subject']}"
    )

    print(
        "\nBIDS session:"
    )

    print(
        f"  {bids_info['session']}"
    )

    print(
        "\nBIDS task:"
    )

    print(
        f"  {bids_info['task']}"
    )

    print(
        "\nBIDS run:"
    )

    print(
        f"  {bids_info['run']}"
    )

    print(
        "\nAll output saved to:"
    )

    print(
        f"  {output_dir}"
    )

    print(
        "\nFiles created:"
    )

    try:

        for file in sorted(
            output_dir.iterdir()
        ):

            print(
                f"  {file.name}"
            )

    except Exception:
        pass


# ============================================================
# RUN
# ============================================================

if __name__ == "__main__":
    main()