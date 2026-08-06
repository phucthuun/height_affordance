# STEP 1 (cluster). Zero-Shot SuperAnimal Inference
# GPU job -- submit with e.g. submit_s01_zeroshot.sbatch
#
# Runs superanimal_humanbody + video-adaptation on raw trial videos for a
# chosen subject/session/run/camera view. Fully headless: no input(), no
# plotting window. Output lands under
#   {data_root}/derivatives/dlc_superanimal/{subID}/{sesID}/{camera_view}/video-zeroshot
# (unified with s02/s03's expected layout -- the original local s01 wrote to
# a different tree than downstream steps read from).

import argparse
import glob
import os

from dlc_cluster_common import add_common_args, resolve_ids, apply_gpu, paths_for, headless_matplotlib

headless_matplotlib()  # must happen before deeplabcut import
import deeplabcut  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description="Zero-shot SuperAnimal inference (cluster)")
    add_common_args(parser)
    args = parser.parse_args()
    apply_gpu(args)

    subID, sesID, runID, camera_view, detector_name = resolve_ids(args)
    paths = paths_for(args.data_root, subID, sesID, camera_view)
    raw_video_dir = paths["raw_video_dir"]
    output_dir = paths["zeroshot_dir"]
    os.makedirs(output_dir, exist_ok=True)

    # BIDS naming: sub-<>_ses-<>_task-<>_run-<>_trial-<>_acq-<View>_beh.mp4
    search_pattern = f"{subID}_{sesID}_task-*_{runID}_trial-*_acq-{camera_view}_beh.mp4"
    video_files = glob.glob(os.path.join(raw_video_dir, search_pattern))

    if not video_files:
        raise FileNotFoundError(
            f"No videos found matching pattern '{search_pattern}' inside: {raw_video_dir}"
        )
    print(f"Found {len(video_files)} videos for processing.")

    print("Running SuperAnimal zero-shot inference + video-adaptation on GPU...")
    deeplabcut.video_inference_superanimal(
        video_files,
        "superanimal_humanbody",
        model_name="rtmpose_x",
        detector_name=detector_name,
        dest_folder=output_dir,
        video_adapt=True,
    )
    print(f"Done. Output written to: {output_dir}")


if __name__ == "__main__":
    main()
