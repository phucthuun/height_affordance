# STEP 3 (cluster). Extract outlier frames for manual correction
# CPU job -- create_new_project() and frame extraction (cv2.imwrite) never
# touch a display, so this is safe to run headlessly on a compute node.
# Only requirement: install opencv-python-headless (not opencv-python) in
# the cluster conda env, so cv2 doesn't try to pull in a Qt/X11 dependency
# it can't use.
#
# (A) DLC project: 17 SuperAnimal bodyparts
# (B) Seeding outliers: reads flagged_trials.txt from s02, and for each trial:
#       (1) finds the after-adaptation SuperAnimal .h5,
#       (2) runs the "jump" outlier algorithm,
#       (3) extracts up to `--numframes2pick` frames evenly across candidates.
#
# NOTE: the actual manual correction of these frames (s04, napari) still has
# to happen on a local machine with a display -- see that script's header.

import argparse
import glob
import os

import cv2
import numpy as np
import pandas as pd
import yaml

import deeplabcut
from deeplabcut.utils import auxiliaryfunctions

from dlc_cluster_common import add_common_args, resolve_ids, paths_for, select_primary_individual

BODYPARTS = [
    'nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear',
    'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow',
    'left_wrist', 'right_wrist', 'left_hip', 'right_hip',
    'left_knee', 'right_knee', 'left_ankle', 'right_ankle'
]


def find_zeroshot_h5(video_path, zeroshot_dir):
    stem = os.path.splitext(os.path.basename(video_path))[0]
    matches = glob.glob(os.path.join(zeroshot_dir, f"{stem}_superanimal_humanbody_snapshot-*.h5"))
    if not matches:
        raise FileNotFoundError(f"No after-adaptation zero-shot .h5 found for {stem} in {zeroshot_dir}")
    if len(matches) > 1:
        print(f"  WARNING: multiple matches for {stem}, using {matches[0]}: {matches}")
    return matches[0]


def jump_outlier_indices(df, epsilon=20):
    """Replicates DLC's outlieralgorithm='jump': flags frames where any
    bodypart moves more than `epsilon` px (Euclidean) from the previous frame."""
    temp_dt = df.diff(axis=0) ** 2
    temp_dt = temp_dt.drop("likelihood", axis=1, level="coords")
    sum_sq = temp_dt.T.groupby(level="bodyparts").sum().T
    idx = df.index[(sum_sq > epsilon ** 2).any(axis=1)].tolist()
    return sorted(set(idx))


def pick_evenly(candidates, n):
    if len(candidates) <= n:
        return candidates
    positions = np.linspace(0, len(candidates) - 1, n).round().astype(int)
    return sorted(set(np.array(candidates)[positions].tolist()))


def seed_outliers_from_zeroshot(config_path, video_path, zeroshot_dir,
                                 epsilon=20, numframes2pick=20, scorer_col_rename=True):
    cfg = auxiliaryfunctions.read_config(config_path)
    vname = os.path.splitext(os.path.basename(video_path))[0]
    tmpfolder = os.path.join(cfg["project_path"], "labeled-data", vname)
    os.makedirs(tmpfolder, exist_ok=True)

    h5_path = find_zeroshot_h5(video_path, zeroshot_dir)
    df = pd.read_hdf(h5_path)
    df = select_primary_individual(df)

    candidates = jump_outlier_indices(df, epsilon=epsilon)
    print(f"{vname}: {len(candidates)} candidate outlier frames (jump algorithm)")
    frames2pick = pick_evenly(candidates, numframes2pick)
    print(f"{vname}: extracting {len(frames2pick)} frames -> {frames2pick}")

    if not frames2pick:
        print(f"  No frames extracted for {vname} (try lowering epsilon).")
        return

    cap = cv2.VideoCapture(video_path)
    nframes = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    strwidth = int(np.ceil(np.log10(max(nframes, 10))))

    for idx in frames2pick:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ok, frame = cap.read()
        if not ok:
            print(f"  WARNING: could not read frame {idx} of {vname}")
            continue
        img_name = f"img{str(idx).zfill(strwidth)}.png"
        cv2.imwrite(os.path.join(tmpfolder, img_name), frame)
    cap.release()

    df_sub = df.loc[frames2pick].copy()

    if scorer_col_rename:
        df_sub.columns = pd.MultiIndex.from_tuples(
            [(cfg["scorer"], bp, coord) for (_, bp, coord) in df_sub.columns],
            names=["scorer", "bodyparts", "coords"],
        )

    df_sub.index = pd.MultiIndex.from_tuples(
        [("labeled-data", vname, f"img{str(idx).zfill(strwidth)}.png") for idx in frames2pick]
    )

    machinefile = os.path.join(tmpfolder, f"machinelabels-iter{cfg['iteration']}.h5")
    df_sub.to_hdf(machinefile, key="df_with_missing", mode="w")
    df_sub.to_csv(os.path.join(tmpfolder, "machinelabels.csv"))
    print(f"  Wrote {machinefile}")


def main():
    parser = argparse.ArgumentParser(description="DLC project setup + outlier seeding (cluster)")
    add_common_args(parser)
    parser.add_argument("--epsilon", type=float, default=20,
                         help="Jump-outlier pixel threshold [default: 20]")
    parser.add_argument("--numframes2pick", type=int, default=12,
                         help="Max frames extracted per flagged trial [default: 12]")
    parser.add_argument("--experimenter", default="Phuc")
    parser.add_argument("--project", default="heightaffordance")
    args = parser.parse_args()

    subID, sesID, camera_view, detector_name = resolve_ids(args)
    paths = paths_for(args.data_root, subID, sesID, camera_view)
    config_dir = paths["dlc_root"]
    raw_video_dir = paths["raw_video_dir"]
    zeroshot_video_dir = paths["zeroshot_dir"]

    with open(os.path.join(zeroshot_video_dir, "flagged_trials.txt")) as f:
        flagged_names = [line.strip() for line in f if line.strip()]
    flagged_videos = [os.path.join(raw_video_dir, name) for name in flagged_names]
    missing = [v for v in flagged_videos if not os.path.exists(v)]
    assert not missing, f"Missing source video(s), check filenames match raw_video_dir exactly: {missing}"

    config_path = deeplabcut.create_new_project(
        project=args.project,
        experimenter=args.experimenter,
        videos=flagged_videos,
        working_directory=config_dir,
        copy_videos=False,
    )

    with open(config_path, "r") as f:
        config_data = yaml.safe_load(f)
    config_data["bodyparts"] = BODYPARTS
    config_data["skeleton"] = []
    with open(config_path, "w") as f:
        yaml.safe_dump(config_data, f, default_flow_style=False)

    for v in flagged_videos:
        seed_outliers_from_zeroshot(
            config_path, v, zeroshot_video_dir,
            epsilon=args.epsilon, numframes2pick=args.numframes2pick,
        )

    print(f"\nDone seeding outliers. config_path = {config_path}")
    print("Sync/copy this project folder to your LOCAL machine and run "
          "s04_dlc-data-preparation.py (napari) there -- refine_labels needs a display.")


if __name__ == "__main__":
    main()
