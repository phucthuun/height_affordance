# STEP 3 (cluster). Extract outlier frames for manual correction
# CPU job -- create_new_project() and frame extraction (cv2.imwrite) headlessly.
#
# Seeding outliers:
#   (1) Filters specifically on 12 limb & torso keypoints (ignoring facial points)
#   (2) Flags frames with large coordinate jumps (Euclidean displacement > epsilon)
#   (3) Flags frames with low confidence (likelihood < conf_threshold)
#   (4) Prioritizes the worst 10 frames per flagged trial

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

# Full 17 SuperAnimal bodyparts for the DLC project schema
BODYPARTS = [
    'nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear',
    'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow',
    'left_wrist', 'right_wrist', 'left_hip', 'right_hip',
    'left_knee', 'right_knee', 'left_ankle', 'right_ankle'
]

# Targeted keypoints for outlier detection & confidence scoring
TARGET_BODYPARTS = [
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


def find_target_outliers(df, target_bps, epsilon=20, conf_threshold=0.4, num_frames=10):
    """Identifies and ranks outlier frames based on coordinate jumps and low confidence

    strictly on target_bps.
    """
    # 1. Filter columns to only include available target bodyparts
    avail_bps = [bp for bp in target_bps if bp in df.columns.get_level_values("bodyparts")]
    if not avail_bps:
        avail_bps = list(df.columns.get_level_values("bodyparts").unique())

    # 2. Low-confidence ranking (worst confidence first)
    lik_cols = [c for c in df.columns if c[-1] == "likelihood" and c[-2] in avail_bps]
    min_conf_per_frame = df[lik_cols].min(axis=1)
    low_conf_candidates = min_conf_per_frame[min_conf_per_frame < conf_threshold].sort_values().index.tolist()

    # 3. Jump ranking (largest Euclidean displacement first)
    xy_cols = [c for c in df.columns if c[-1] in ("x", "y") and c[-2] in avail_bps]
    diff_sq = df[xy_cols].diff(axis=0) ** 2
    sum_sq = diff_sq.T.groupby(level="bodyparts").sum().T
    max_jump_per_frame = np.sqrt(sum_sq.max(axis=1))
    jump_candidates = max_jump_per_frame[max_jump_per_frame > epsilon].sort_values(ascending=False).index.tolist()

    # 4. Hybrid allocation: allocate half to lowest confidence, half to largest jumps
    picked = []
    half_quota = num_frames // 2

    for idx in low_conf_candidates:
        if len(picked) >= half_quota:
            break
        if idx not in picked:
            picked.append(idx)

    for idx in jump_candidates:
        if len(picked) >= num_frames:
            break
        if idx not in picked:
            picked.append(idx)

    # 5. Backfill if quota remains from candidates
    for idx in low_conf_candidates + jump_candidates:
        if len(picked) >= num_frames:
            break
        if idx not in picked:
            picked.append(idx)

    # Fallback: if no frames tripped the thresholds, take the N lowest-confidence frames
    if not picked:
        picked = min_conf_per_frame.sort_values().head(num_frames).index.tolist()

    return sorted(picked)


def seed_outliers_from_zeroshot(config_path, video_path, zeroshot_dir,
                                 epsilon=20, conf_threshold=0.4, numframes2pick=10, scorer_col_rename=True):
    cfg = auxiliaryfunctions.read_config(config_path)
    vname = os.path.splitext(os.path.basename(video_path))[0]
    tmpfolder = os.path.join(cfg["project_path"], "labeled-data", vname)
    os.makedirs(tmpfolder, exist_ok=True)

    h5_path = find_zeroshot_h5(video_path, zeroshot_dir)
    df = pd.read_hdf(h5_path)
    df = select_primary_individual(df)

    frames2pick = find_target_outliers(
        df,
        target_bps=TARGET_BODYPARTS,
        epsilon=epsilon,
        conf_threshold=conf_threshold,
        num_frames=numframes2pick,
    )
    print(f"{vname}: extracted {len(frames2pick)} priority outlier frames -> {frames2pick}")

    if not frames2pick:
        print(f"  No frames extracted for {vname}.")
        return

    cap = cv2.VideoCapture(video_path)
    nframes = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    strwidth = int(np.ceil(np.log10(max(nframes, 10))))

    valid_frames = []
    for idx in frames2pick:
        if idx >= nframes:
            continue
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ok, frame = cap.read()
        if not ok:
            print(f"  WARNING: could not read frame {idx} of {vname}")
            continue
        img_name = f"img{str(idx).zfill(strwidth)}.png"
        cv2.imwrite(os.path.join(tmpfolder, img_name), frame)
        valid_frames.append(idx)
    cap.release()

    df_sub = df.loc[valid_frames].copy()

    if scorer_col_rename:
        df_sub.columns = pd.MultiIndex.from_tuples(
            [(cfg["scorer"], bp, coord) for (_, bp, coord) in df_sub.columns],
            names=["scorer", "bodyparts", "coords"],
        )

    df_sub.index = pd.MultiIndex.from_tuples(
        [("labeled-data", vname, f"img{str(idx).zfill(strwidth)}.png") for idx in valid_frames]
    )

    machinefile = os.path.join(tmpfolder, f"machinelabels-iter{cfg['iteration']}.h5")
    df_sub.to_hdf(machinefile, key="df_with_missing", mode="w")
    df_sub.to_csv(os.path.join(tmpfolder, "machinelabels.csv"))
    print(f"  Wrote {machinefile}")


def main():
    parser = argparse.ArgumentParser(description="DLC project setup + outlier seeding (cluster)")
    add_common_args(parser)
    parser.add_argument("--epsilon", type=float, default=20.0,
                         help="Jump-outlier pixel threshold [default: 20]")
    parser.add_argument("--conf-threshold", type=float, default=0.4,
                         help="Likelihood threshold for flagging low confidence [default: 0.4]")
    parser.add_argument("--numframes2pick", type=int, default=10,
                         help="Max frames extracted per flagged trial [default: 10]")
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
    
    # Ensures up to 20 trials are handled
    flagged_videos = [os.path.join(raw_video_dir, name) for name in flagged_names[:20]]
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
            epsilon=args.epsilon,
            conf_threshold=args.conf_threshold,
            numframes2pick=args.numframes2pick,
        )

    print(f"\nDone seeding outliers. config_path = {config_path}")
    print("Sync/copy this project folder to your LOCAL machine and run s04 (napari).")


if __name__ == "__main__":
    main()