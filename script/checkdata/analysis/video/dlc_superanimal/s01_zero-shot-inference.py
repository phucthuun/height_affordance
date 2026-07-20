# STEP 1. Zero-Shot SuperAnimal Inference
# This script uses superanimal_humanbody and video-adaptation on all raw trial videos 
# Output: prediction for each trial land in video-zeroshot\ as .h5/.json/_labeled_after_adapt.mp4

import os
import glob
import deeplabcut
import pandas as pd

# 1. Define Paths
raw_video_dir   = r"C:\Data\Research\10_Data\derivatives\syncdata\sub-Maximilian\ses-S001\training_video"
output_dir      = r"C:\Data\Research\10_Data\derivatives\dlc_superanimal\sub-Maximilian\ses-S001\video-zeroshot"
os.makedirs(output_dir, exist_ok=True)

# Find all 64 target trial videos
video_files = glob.glob(os.path.join(raw_video_dir, "*.mp4"))
# print(f"Found {len(video_files)} videos for processing.")

# 2. Run Zero-Shot SuperAnimal Inference
print("Running initial SuperAnimal zero-shot inference...")
deeplabcut.video_inference_superanimal(
    video_files, 
    "superanimal_humanbody", 
    model_name="rtmpose_x", 
    detector_name="fasterrcnn_mobilenet_v3_large_fpn", #for local: "fasterrcnn_mobilenet_v3_large_fpn"; for tardis: "fasterrcnn_resnet50_fpn_v2"
    dest_folder=output_dir,
    video_adapt=True
)
