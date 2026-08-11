# STEP 2. QC ranking + auto-flagging
# This script reads every after-adaptation .h5, scores mean/worst-frame confidence from step 1 
# Output: 
# (1) qc_ranking.csv 
# (2) flagged_trials.txt documents the trials worth correcting

import pandas as pd, glob, os, re

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

out_root = rf"C:\Data\Research\10_Data\derivatives\dlc_superanimal\{subID}\{sesID}\{camera_view}\video-zeroshot"

MEAN_CONF_THRESHOLD  = 0.6
WORST_CONF_THRESHOLD = 0.4

rows = []
# Only the after-adaptation predictions (skip any leftover "*_before_adapt*" h5)
for h5 in sorted(glob.glob(os.path.join(out_root, "*snapshot-*.h5"))):
    df = pd.read_hdf(h5)
    lik_cols = [c for c in df.columns if c[-1] == "likelihood"]
    mean_conf = df[lik_cols].mean().mean()
    min_conf  = df[lik_cols].mean(axis=1).min()
    rows.append((os.path.basename(h5), round(mean_conf, 3), round(min_conf, 3)))

report = pd.DataFrame(rows, columns=["file", "mean_conf", "worst_frame_conf"])
report = report.sort_values("worst_frame_conf")
report.to_csv(os.path.join(out_root, "qc_ranking.csv"), index=False)
print(report.head(20))

def h5_to_video_filename(h5_filename):
    """'trial-001_superanimal_humanbody_snapshot-rtmpose_x-004_fasterrcnn_....h5'
    -> 'trial-001.mp4'
    Verify this against your raw_video_dir naming before trusting it."""
    stem = h5_filename.split("_superanimal_humanbody_snapshot-")[0]
    return stem+'.mp4'

flagged = report[
    (report["mean_conf"] < MEAN_CONF_THRESHOLD) |
    (report["worst_frame_conf"] < WORST_CONF_THRESHOLD)
]

flagged_names = [h5_to_video_filename(f) for f in flagged["file"]]

with open(os.path.join(out_root, "flagged_trials.txt"), "w") as f:
    for name in flagged_names[:10]:
        f.write(name + "\n")

print(f"\nFlagged {len(flagged_names)} / {len(report)} trials -> flagged_trials.txt")
print(flagged_names)