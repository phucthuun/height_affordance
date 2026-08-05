# STEP 2 (cluster). QC ranking + auto-flagging
# CPU job -- lightweight pandas/HDF work, no GPU needed. Can be chained
# right after s01 in the same sbatch script, or submitted separately on a
# CPU partition.
#
# Reads every after-adaptation .h5 from s01, scores mean/worst-frame
# confidence.
# Output:
#   (1) qc_ranking.csv
#   (2) flagged_trials.txt  -- trials worth manually correcting

import argparse
import glob
import os

import pandas as pd

from dlc_cluster_common import add_common_args, resolve_ids, paths_for

MEAN_CONF_THRESHOLD = 0.6
WORST_CONF_THRESHOLD = 0.4


def h5_to_video_filename(h5_filename):
    """'trial-001_superanimal_humanbody_snapshot-rtmpose_x-004_fasterrcnn_....h5'
    -> 'trial-001.mp4'
    Verify this against your raw_video_dir naming before trusting it."""
    stem = h5_filename.split("_superanimal_humanbody_snapshot-")[0]
    return stem + ".mp4"


def main():
    parser = argparse.ArgumentParser(description="Zero-shot QC ranking (cluster)")
    add_common_args(parser)
    parser.add_argument("--max-flagged", type=int, default=10,
                         help="Max number of trials written to flagged_trials.txt [default: 10]")
    args = parser.parse_args()

    subID, sesID, runID, camera_view, detector_name = resolve_ids(args)
    paths = paths_for(args.data_root, subID, sesID, camera_view)
    out_root = paths["zeroshot_dir"]

    rows = []
    for h5 in sorted(glob.glob(os.path.join(out_root, "*snapshot-*.h5"))):
        df = pd.read_hdf(h5)
        lik_cols = [c for c in df.columns if c[-1] == "likelihood"]
        mean_conf = df[lik_cols].mean().mean()
        min_conf = df[lik_cols].mean(axis=1).min()
        rows.append((os.path.basename(h5), round(mean_conf, 3), round(min_conf, 3)))

    if not rows:
        raise FileNotFoundError(f"No *snapshot-*.h5 files found in {out_root}. Run s01 first.")

    report = pd.DataFrame(rows, columns=["file", "mean_conf", "worst_frame_conf"])
    report = report.sort_values("worst_frame_conf")
    report.to_csv(os.path.join(out_root, "qc_ranking.csv"), index=False)
    print(report.head(20))

    flagged = report[
        (report["mean_conf"] < MEAN_CONF_THRESHOLD)
        | (report["worst_frame_conf"] < WORST_CONF_THRESHOLD)
    ]
    flagged_names = [h5_to_video_filename(f) for f in flagged["file"]]

    with open(os.path.join(out_root, "flagged_trials.txt"), "w") as f:
        for name in flagged_names[: args.max_flagged]:
            f.write(name + "\n")

    print(f"\nFlagged {len(flagged_names)} / {len(report)} trials -> flagged_trials.txt")
    print(flagged_names)


if __name__ == "__main__":
    main()
