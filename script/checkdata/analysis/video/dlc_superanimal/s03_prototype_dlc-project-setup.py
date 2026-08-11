# STEP 3. Extract outlier frames for manual correction
# This script puts outlier into a DLC projects
# (A) DLC project: 17 SuperAnimal bodyparts
# (B) Seeding outliers: It reads the flagged_trials.txt from step 2, and for each trial:     
#       (1) finds the after-adaptation SuperAnimal .h5,
#       (2) runs the "jump" outlier algorithm (find frames where any bodypart moves more than `epsilon` px from the previous frame),
#       (3) extracts up to 20 frames (`numframes2pick`) frames evenly across the candidate list  




import os, glob, re
import numpy as np
import pandas as pd
import cv2
import deeplabcut
from deeplabcut.utils import auxiliaryfunctions

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

config_dir = rf"C:\Data\Research\10_Data\derivatives\dlc_superanimal\{subID}\{sesID}\{camera_view}"
raw_video_dir       = rf"C:\Data\Research\10_Data\derivatives\syncdata\{subID}\{sesID}\video"
zeroshot_video_dir  = rf"C:\Data\Research\10_Data\derivatives\dlc_superanimal\{subID}\{sesID}\{camera_view}\video-zeroshot"

with open(os.path.join(zeroshot_video_dir, "flagged_trials.txt")) as f:
    flagged_names = [line.strip() for line in f if line.strip()]
# back to raw_video_dir: we need clean, unlabeled source video for
# project registration and frame extraction, not the annotated video-zeroshot outputs
flagged_videos = [os.path.join(raw_video_dir, name) for name in flagged_names]
assert all(os.path.exists(v) for v in flagged_videos), "check filenames match source video_dir exactly"

# ----------------------------
# PREPARE PROJECT (unchanged from before)
# ----------------------------
config_path = deeplabcut.create_new_project(
    project="heightaffordance",
    experimenter="Phuc",
    videos=flagged_videos,
    working_directory=config_dir,
    copy_videos=False,
)

import yaml
with open(config_path, "r") as f:
    config_data = yaml.safe_load(f)

config_data["bodyparts"] = [
    'nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear',
    'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow',
    'left_wrist', 'right_wrist', 'left_hip', 'right_hip',
    'left_knee', 'right_knee', 'left_ankle', 'right_ankle'
]
config_data["skeleton"] = []  # clear placeholder skeleton referencing bodypart1/2

with open(config_path, "w") as f:
    yaml.safe_dump(config_data, f, default_flow_style=False)

cfg = auxiliaryfunctions.read_config(config_path)


# ----------------------------
# CUSTOM OUTLIER SEEDING (reuse SuperAnimal predictions)
# ----------------------------
def find_zeroshot_h5(video_path, zeroshot_dir):
    """Locate the (after-adaptation) SuperAnimal .h5 for a given raw video."""
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
    idx = df.index[(sum_sq > epsilon**2).any(axis=1)].tolist()
    return sorted(set(idx))


def pick_evenly(candidates, n):
    """Evenly sample up to n frame indices across the candidate list,
    for temporal diversity rather than clumping."""
    if len(candidates) <= n:
        return candidates
    positions = np.linspace(0, len(candidates) - 1, n).round().astype(int)
    return sorted(set(np.array(candidates)[positions].tolist()))

def select_primary_individual(df):
    """Collapse a 4-level (scorer/individuals/bodyparts/coords) SuperAnimal
    output down to 3 levels (scorer/bodyparts/coords), matching single-animal
    project format. If >1 individual appears, keep the most confident one."""
    if "individuals" not in df.columns.names:
        return df

    individuals = df.columns.get_level_values("individuals").unique().tolist()
    if len(individuals) == 1:
        return df.xs(individuals[0], level="individuals", axis=1)

    conf_by_ind = {}
    for ind in individuals:
        sub = df.xs(ind, level="individuals", axis=1)
        lik_cols = [c for c in sub.columns if c[-1] == "likelihood"]
        conf_by_ind[ind] = sub[lik_cols].mean().mean()
    best = max(conf_by_ind, key=conf_by_ind.get)
    print(f"  Multiple individuals detected {individuals}; keeping highest-confidence: {best}")
    return df.xs(best, level="individuals", axis=1)

def seed_outliers_from_zeroshot(config_path, video_path, zeroshot_dir,
                                 epsilon=20, numframes2pick=20, scorer_col_rename=True):
    cfg = auxiliaryfunctions.read_config(config_path)
    vname = os.path.splitext(os.path.basename(video_path))[0]
    tmpfolder = os.path.join(cfg["project_path"], "labeled-data", vname)
    os.makedirs(tmpfolder, exist_ok=True)

    h5_path = find_zeroshot_h5(video_path, zeroshot_dir)
    df = pd.read_hdf(h5_path)
    df = select_primary_individual(df)          # <-- new: drop to 3 levels
    print(f"  columns levels: {df.columns.names}")  # sanity print, remove once confirmed

    candidates = jump_outlier_indices(df, epsilon=epsilon)
    print(f"{vname}: {len(candidates)} candidate outlier frames (jump algorithm)")
    frames2pick = pick_evenly(candidates, numframes2pick)
    print(f"{vname}: extracting {len(frames2pick)} frames -> {frames2pick}")

    if not frames2pick:
        print(f"  No frames extracted for {vname} (try lowering epsilon).")
        return

    # --- extract raw (unlabeled) frame images ---
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

    # --- build machinelabels-iter<N>.h5 in DLC's expected schema ---
    df_sub = df.loc[frames2pick].copy()

    if scorer_col_rename:
        # Rename the scorer level to the project's own scorer, so it plays
        # nicely later when merge_datasets combines it with CollectedData_<scorer>.h5
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


# --- once satisfied, run on the rest ---
for v in flagged_videos:
    seed_outliers_from_zeroshot(config_path, v, zeroshot_video_dir, numframes2pick=12)

print("\nDone seeding outliers. Now run: deeplabcut.refine_labels(config_path)")