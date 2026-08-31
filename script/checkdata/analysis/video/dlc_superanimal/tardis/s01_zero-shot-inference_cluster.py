# STEP 1 (cluster). Zero-Shot SuperAnimal Inference
# GPU job -- submit with e.g. submit_s01_zeroshot.sbatch
#
# Runs superanimal_humanbody + video-adaptation on raw trial videos for a
# chosen subject/session/camera view. Fully headless: no input(), no
# plotting window. Output lands under
#   {data_root}/derivatives/dlc_superanimal/{subID}/{sesID}/{camera_view}/video-zeroshot
# (unified with s02/s03's expected layout -- the original local s01 wrote to
# a different tree than downstream steps read from).
#
# RUNS ARE POOLED BY DEFAULT (--run all): each subject has 5 runs and may
# change clothing (pants / judogi) between them, and every downstream step
# (QC, outlier seeding, training) already pools everything found here
# regardless of run. So by default this script processes every run's
# videos for the subject/session/camera_view in a single GPU job, instead
# of requiring 5 separate submissions. Use --run to restrict to one run or
# a specific subset (e.g. to re-run inference on a single run that failed),
# see dlc_cluster_common.py's module docstring for the full rationale.

import argparse
import glob
import os

from dlc_cluster_common import (
    add_common_args, resolve_ids, resolve_run_ids, apply_gpu, paths_for, headless_matplotlib,
)

headless_matplotlib()  # must happen before deeplabcut import
import deeplabcut  # noqa: E402


def find_video_files(raw_video_dir, subID, sesID, camera_view, run_ids):
    """BIDS naming: sub-<>_ses-<>_task-<>_run-<>_trial-<>_acq-<View>_beh.mp4
    run_ids: None -> pool every run ('run-*'); otherwise a list of
    normalized runIDs e.g. ['run-001', 'run-003'] to restrict to."""
    run_tokens = ["run-*"] if run_ids is None else run_ids
    video_files = []
    for run_token in run_tokens:
        pattern = f"{subID}_{sesID}_task-*_{run_token}_trial-*_acq-{camera_view}_beh.mp4"
        video_files.extend(glob.glob(os.path.join(raw_video_dir, pattern)))
    return sorted(set(video_files))


def main():
    parser = argparse.ArgumentParser(description="Zero-shot SuperAnimal inference (cluster)")
    add_common_args(parser)
    args = parser.parse_args()
    apply_gpu(args)

    subID, sesID, camera_view, detector_name = resolve_ids(args)
    run_ids = resolve_run_ids(args)
    paths = paths_for(args.data_root, subID, sesID, camera_view)
    raw_video_dir = paths["raw_video_dir"]
    output_dir = paths["zeroshot_dir"]
    os.makedirs(output_dir, exist_ok=True)

    video_files = find_video_files(raw_video_dir, subID, sesID, camera_view, run_ids)

    if not video_files:
        run_desc = "all runs" if run_ids is None else ", ".join(run_ids)
        raise FileNotFoundError(
            f"No videos found for {run_desc} inside: {raw_video_dir}"
        )
    print(f"Found {len(video_files)} videos for processing "
          f"({'all runs' if run_ids is None else ', '.join(run_ids)}).")
    for v in video_files:
        print(f"  - {os.path.basename(v)}")

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
