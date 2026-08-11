# STEP 1. Zero-Shot SuperAnimal Inference
# This script uses superanimal_humanbody and video-adaptation on raw trial videos
# for a chosen subject/session/run/camera view.
# Output: prediction for each trial lands in video-zeroshot\ as .h5/.json/_labeled_after_adapt.mp4

import os
import re
import glob
import deeplabcut
import pandas as pd

# 1. Interactive Target Selection
print("============ SuperAnimal Zero-Shot Inference ============")
sub_in = input("Enter Subject ID (e.g., MH9HXJ) [default: MH9HXJ]: ").strip() or "MH9HXJ"
ses_in = input("Enter Session ID (e.g., S001) [default: S001]: ").strip() or "S001"
run_in = input("Enter Run ID (e.g., 002) [default: 002]: ").strip() or "002"
cam_in = input("Camera view - 's' for SideView, 'u' for UpperView [default: s]: ").strip().lower() or "s"
mach_in = input("Training machine - 'local' or 'tardis' [default: local]: ").strip().lower() or "local"

subLabel = re.sub(r'^sub-', '', sub_in)
sesLabel = re.sub(r'^ses-', '', ses_in)
runLabel = re.sub(r'^run-', '', run_in).zfill(3)

subID = f"sub-{subLabel}"
sesID = f"ses-{sesLabel}"
runID = f"run-{runLabel}"

camera_view = "UpperView" if cam_in == "u" else "SideView"
detector_name = "fasterrcnn_resnet50_fpn_v2" if mach_in == "tardis" else "fasterrcnn_mobilenet_v3_large_fpn"

print(f" -> {subID} | {sesID} | {runID} | View: {camera_view} | Machine: {mach_in} | Detector: {detector_name}")

# 2. Define Paths
raw_video_dir = rf"C:\Data\Research\10_Data\derivatives\syncdata\{subID}\{sesID}\video"
output_dir    = rf"C:\Data\Research\10_Data\derivatives\dlc_superanimal\{subID}\{sesID}\{camera_view}\video-zeroshot"
os.makedirs(output_dir, exist_ok=True)

# Find all target trial videos for this subject/session/run/camera view
# BIDS naming: sub-<>_ses-<>_task-<>_run-<>_trial-<>_acq-<View>_beh.mp4
search_pattern = f"{subID}_{sesID}_task-*_{runID}_trial-*_acq-{camera_view}_beh.mp4"
video_files = glob.glob(os.path.join(raw_video_dir, search_pattern))

if not video_files:
    raise FileNotFoundError(
        f"No videos found matching pattern '{search_pattern}' inside: {raw_video_dir}"
    )
print(f"Found {len(video_files)} videos for processing.")

# 3. Run Zero-Shot SuperAnimal Inference
print("Running initial SuperAnimal zero-shot inference...")
deeplabcut.video_inference_superanimal(
    video_files,
    "superanimal_humanbody",
    model_name="rtmpose_x",
    detector_name=detector_name,  # local: fasterrcnn_mobilenet_v3_large_fpn; tardis: fasterrcnn_resnet50_fpn_v2
    dest_folder=output_dir,
    video_adapt=True
)