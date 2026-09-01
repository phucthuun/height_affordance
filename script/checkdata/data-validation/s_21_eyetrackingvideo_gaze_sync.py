import pyxdf
import cv2
import numpy as np
import os
import tkinter as tk
from tkinter import filedialog


# =========================
# FILE PICKER
# =========================
def select_file(title, filetypes):
    root = tk.Tk()
    root.withdraw()
    return filedialog.askopenfilename(title=title, filetypes=filetypes)


# =========================
# LOAD XDF
# =========================
def load_xdf(path):
    data, _ = pyxdf.load_xdf(path)
    return data


def get_stream(streams, name):
    return [s for s in streams if s["info"]["name"][0] == name]


# =========================
# PARSE EVENTS
# =========================
def parse_events(event_stream):
    markers = [
        s[0] if isinstance(s, list) else str(s)
        for s in event_stream["time_series"]
    ]
    times = np.array(event_stream["time_stamps"])
    return list(zip(times, markers))


# =========================
# PARSE GAZE
# =========================
def parse_gaze(gaze_stream):
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

    return times, np.array(x), np.array(y)


# =========================
# INTERPOLATION
# =========================
def gaze_at_time(t, gaze_t, gx, gy):
    if len(gaze_t) < 2:
        return None

    x = np.interp(t, gaze_t, gx)
    y = np.interp(t, gaze_t, gy)

    if np.isnan(x) or np.isnan(y):
        return None

    return int(x), int(y)


# =========================
# MAIN EXPORT
# =========================
def main():

    mp4_path = select_file("Select MP4", [("MP4", "*.mp4")])
    xdf_path = select_file("Select XDF", [("XDF", "*.xdf")])

    streams = load_xdf(xdf_path)

    event_stream = get_stream(streams, "EyeTracker Device_Neon Events")[0]
    gaze_stream = get_stream(streams, "EyeTracker Device_Neon Gaze")[0]

    events = parse_events(event_stream)
    gaze_t, gx, gy = parse_gaze(gaze_stream)

    # -------------------------
    # ALIGN TIMEBASE
    # -------------------------
    start_time = events[0][0]
    events = [(t - start_time, m) for t, m in events]
    gaze_t = gaze_t - start_time

    # -------------------------
    # VIDEO
    # -------------------------
    cap = cv2.VideoCapture(mp4_path)

    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    # -------------------------
    # OUTPUT FOLDER
    # -------------------------
    out_dir = r"C:\Users\fhoffmann\Desktop\eye_segments"
    os.makedirs(out_dir, exist_ok=True)

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")


    # -------------------------
    # BUILD SEGMENTS
    # -------------------------
    neutral_events = [(t, m) for t, m in events if "Fight" in m]
    FIGHT_PAD = 4.5  # seconds

    fight_events = [(t, m) for t, m in events if "Fight" in m]

    segments = []

    for i in range(len(fight_events) - 1):
        t0, m0 = fight_events[i]
        t1, _ = fight_events[i + 1]

        start = t0 - FIGHT_PAD
        end = t1 - FIGHT_PAD

        # safety: avoid negative start times
        start = max(0, start)

        segments.append((start, end, m0))

    print(f"Segments: {len(segments)}")

    # -------------------------
    # PROCESS EACH SEGMENT
    # -------------------------
    for idx, (t0, t1, label) in enumerate(segments):

        cap.set(cv2.CAP_PROP_POS_MSEC, t0 * 1000)

        out_path = os.path.join(out_dir, f"{idx:03d}_{label}.mp4")
        writer = cv2.VideoWriter(out_path, fourcc, fps, (width, height))

        print(f"Writing {out_path}")

        while True:
            current_t = cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0

            if current_t > t1:
                break

            ret, frame = cap.read()
            if not ret:
                break

            gaze = gaze_at_time(current_t, gaze_t, gx, gy)

            if gaze is not None:
                cv2.circle(frame, gaze, 8, (0, 0, 255), -1)

            cv2.putText(
                frame,
                label,
                (30, 60),
                cv2.FONT_HERSHEY_SIMPLEX,
                1,
                (0, 255, 255),
                2
            )

            writer.write(frame)

        writer.release()

    cap.release()
    print("Done.")


if __name__ == "__main__":
    main()


