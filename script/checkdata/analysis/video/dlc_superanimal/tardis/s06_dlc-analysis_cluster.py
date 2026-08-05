# STEP 6 (cluster). Analyze on all videos
# GPU job for analyze_videos() (inference), the rest (filterpredictions,
# create_labeled_video) is CPU/ffmpeg but cheap to leave on the same
# allocation. Submit with submit_s06_analysis.sbatch.

import argparse
import glob
import os
from pathlib import Path

from dlc_cluster_common import add_common_args, resolve_ids, apply_gpu, paths_for, headless_matplotlib

headless_matplotlib()  # create_labeled_video / filterpredictions can trigger plotting
import deeplabcut  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description="DLC full-video analysis (cluster)")
    add_common_args(parser)
    parser.add_argument("--project", default="heightaffordance")
    args = parser.parse_args()
    apply_gpu(args)

    subID, sesID, runID, camera_view, detector_name = resolve_ids(args)
    paths = paths_for(args.data_root, subID, sesID, camera_view)
    base_dir = Path(paths["dlc_root"])
    raw_video_dir = paths["raw_video_dir"]
    final_out = paths["estimation_dir"]

    matching_configs = list(base_dir.glob(f"{args.project}-*/config.yaml"))
    if not matching_configs:
        raise FileNotFoundError(f"Could not find any '{args.project}-*/config.yaml' inside {base_dir}")
    config_path = str(matching_configs[0])
    print(f"Found config at: {config_path}")

    os.makedirs(final_out, exist_ok=True)
    search_pattern = f"*acq-{camera_view}_beh.mp4"
    all_videos = sorted(glob.glob(os.path.join(raw_video_dir, search_pattern)))
    if not all_videos:
        raise FileNotFoundError(f"No videos matching '{search_pattern}' in {raw_video_dir}")
    print(f"Found {len(all_videos)} videos to analyze.")

    deeplabcut.analyze_videos(config_path, all_videos, videotype=".mp4",
                               destfolder=final_out, save_as_csv=True)
    deeplabcut.filterpredictions(config_path, all_videos, destfolder=final_out)
    deeplabcut.create_labeled_video(config_path, all_videos, destfolder=final_out, filtered=True)
    print(f"Done. Output written to: {final_out}")


if __name__ == "__main__":
    main()
