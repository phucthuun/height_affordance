# STEO 6. Analyze on all videos
import os, glob
import deeplabcut
import re
from pathlib import Path

# 1. Interactive Target Selection
print("============ SuperAnimal Zero-Shot Inference ============")
sub_in = input("Enter Subject ID (e.g., MH9HXJ): ").strip() or "MH9HXJ"
ses_in = input("Enter Session ID (e.g., S001): ").strip() or "S001"
run_in = input("Enter Run ID (e.g., 001): ").strip() or "001"
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

# Base directory where heightaffordance-* subfolder lives
base_dir = Path(rf"C:\Data\Research\10_Data\derivatives\dlc_superanimal\{subID}\{sesID}\{camera_view}")

# Find matching config.yaml file(s) using wildcards
matching_configs = list(base_dir.glob("heightaffordance-*/config.yaml"))

if matching_configs:
    config_path = str(matching_configs[0])  # Takes the first match found
    print(f"\nFound config at: {config_path}")
else:
    print(f"\nError: Could not find any 'heightaffordance-*/config.yaml' inside {base_dir}")
    config_path = None
    
raw_video_dir = rf"C:\Data\Research\10_Data\derivatives\syncdata\{subID}\{sesID}\video"
final_out = rf"C:\Data\Research\10_Data\derivatives\dlc_superanimal\{subID}\{sesID}\{camera_view}\video-estimation"

os.makedirs(final_out, exist_ok=True)
search_pattern = f"*acq-{camera_view}_beh.mp4"
all_videos = sorted(glob.glob(os.path.join(raw_video_dir, search_pattern)))

deeplabcut.analyze_videos(config_path, all_videos, videotype=".mp4", destfolder=final_out, save_as_csv=True)
deeplabcut.filterpredictions(config_path, all_videos, destfolder=final_out)
deeplabcut.create_labeled_video(config_path, all_videos, destfolder=final_out, filtered=True)