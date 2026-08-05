# STEP 5 (cluster). Merge refined labels -> train -> evaluate
# GPU job -- this is the step that benefits most from the cluster's GPU
# nodes. Submit with submit_s05_training.sbatch.
#
# Prereq: s04 (napari refine_labels, LOCAL ONLY) must have been completed
# and each labeled-data/<trial> folder must contain a CollectedData_<scorer>.h5
# before merge_datasets() will accept it. Sync the corrected project folder
# from your local machine back to BeeGFS before running this.

import argparse
from pathlib import Path

from dlc_cluster_common import add_common_args, resolve_ids, apply_gpu, paths_for, headless_matplotlib

headless_matplotlib()  # evaluate_network(plotting=True) needs a non-interactive backend
import deeplabcut  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description="DLC training + evaluation (cluster)")
    add_common_args(parser)
    parser.add_argument("--maxiters", type=int, default=20000)
    parser.add_argument("--displayiters", type=int, default=100)
    parser.add_argument("--saveiters", type=int, default=1000)
    parser.add_argument("--project", default="heightaffordance")
    args = parser.parse_args()
    apply_gpu(args)

    subID, sesID, runID, camera_view, detector_name = resolve_ids(args)
    paths = paths_for(args.data_root, subID, sesID, camera_view)
    base_dir = Path(paths["dlc_root"])

    matching_configs = list(base_dir.glob(f"{args.project}-*/config.yaml"))
    if not matching_configs:
        raise FileNotFoundError(
            f"Could not find any '{args.project}-*/config.yaml' inside {base_dir}. "
            f"Run s03 (and complete s04 refinement locally) first."
        )
    config_path = str(matching_configs[0])
    print(f"Found config at: {config_path}")

    # Transfer learning from SuperAnimal-HumanBody isn't used here (kept off,
    # matching the original script's choice) -- ImageNet-pretrained backbone,
    # trained for longer (maxiters) instead of fewer transfer-learning epochs.
    deeplabcut.merge_datasets(config_path)  # only proceeds once every folder has CollectedData_*.h5
    deeplabcut.create_training_dataset(config_path)
    deeplabcut.train_network(
        config_path,
        maxiters=args.maxiters,
        displayiters=args.displayiters,
        saveiters=args.saveiters,
    )
    deeplabcut.evaluate_network(config_path, plotting=True)
    print("Training + evaluation complete.")


if __name__ == "__main__":
    main()
