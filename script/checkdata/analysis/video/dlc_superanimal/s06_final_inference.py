# STEO 6. Analyze on all videos
import os, glob
import deeplabcut

config_path = r"C:\Data\Research\10_Data\derivatives\dlc_superanimal\sub-Maximilian\ses-S001\heightaffordance-Phuc-2026-07-19\config.yaml"
raw_video_dir = r"C:\Data\Research\10_Data\derivatives\syncdata\sub-Maximilian\ses-S001\video"
final_out = r"C:\Data\Research\10_Data\derivatives\dlc_superanimal\sub-Maximilian\ses-S001\video-estimation"

os.makedirs(final_out, exist_ok=True)
all_videos = sorted(glob.glob(os.path.join(raw_video_dir, "*4_acq-SideView_desc-contrasted_beh.mp4")))

# deeplabcut.analyze_videos(config_path, all_videos, videotype=".mp4", destfolder=final_out, save_as_csv=True)
deeplabcut.filterpredictions(config_path, all_videos, destfolder=final_out)
deeplabcut.create_labeled_video(config_path, all_videos, destfolder=final_out, filtered=True)