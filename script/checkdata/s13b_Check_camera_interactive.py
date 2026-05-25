import cv2
import pandas as pd
import os
import tkinter as tk
from tkinter import filedialog

def select_path(title, file_mode=True, file_types=None):
    """Helper to open a file or folder dialog."""
    root = tk.Tk()
    root.withdraw()  # Hide the main tkinter window
    root.attributes("-topmost", True)  # Bring dialog to front
    if file_mode:
        path = filedialog.askopenfilename(title=title, filetypes=file_types)
    else:
        path = filedialog.askdirectory(title=title)
    root.destroy()
    return path

# --- 1. INTERACTIVE PATH SELECTION ---
print("Please select the CSV Sync Report...")
csv_path = select_path("Select Sync Report CSV", file_types=[("CSV Files", "*.csv")])

print("Please select the Raw Video file...")
video_path = select_path("Select Video File", file_types=[("Video Files", "*.avi *.mp4 *.mkv")])

print("Please select where to save the results...")
SAVE_DIR = select_path("Select Output Folder", file_mode=False)

if not all([csv_path, video_path, SAVE_DIR]):
    print("Error: Missing file or folder selection. Exiting.")
    exit()

# Auto-generate output filename based on original video name
video_filename = os.path.basename(video_path)
output_filename = f"TRIMMED_{os.path.splitext(video_filename)[0]}.mp4"
output_path = os.path.join(SAVE_DIR, output_filename)

# --- 2. LOAD DATA & CALCULATE BOUNDARIES ---
df = pd.read_csv(csv_path)

# Filter for the specific camera (assuming Cam0 based on your original code)
# If your CSV uses a different column name for frames, adjust here
marker_map = dict(zip(df['Cam0_Frame'], df['Event']))

start_frame = int(df['Cam0_Frame'].min())
end_frame = int(df['Cam0_Frame'].max())

print(f"Experiment detected from Frame {start_frame} to {end_frame}.")

# --- 3. VIDEO SETUP ---
cap = cv2.VideoCapture(video_path)
width  = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
fps    = cap.get(cv2.CAP_PROP_FPS)

# Jump directly to the start
cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))

print(f"Processing... Saving to: {output_path}")

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break

    # Get current frame index
    current_frame = int(cap.get(cv2.CAP_PROP_POS_FRAMES))

    if current_frame > end_frame:
        print("Reached last marker. Closing file...")
        break

    # --- 4. OVERLAY LOGIC ---
    if current_frame in marker_map:
        marker_text = marker_map[current_frame]
        cv2.rectangle(frame, (10, 10), (500, 70), (0, 0, 0), -1)
        cv2.putText(frame, f"MARKER: {marker_text}", (20, 50), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 0), 2)

    cv2.putText(frame, f"Frame: {current_frame}", (20, 110), 
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)

    out.write(frame)

    # Preview (Press 'Esc' to cancel)
    cv2.imshow('Saving Trimmed Video...', frame)
    if cv2.waitKey(1) & 0xFF == 27:
        break

# --- 5. CLEANUP ---
cap.release()
out.release()
cv2.destroyAllWindows()
print(f"Done! Total frames saved: {end_frame - start_frame}")