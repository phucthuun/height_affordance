"""
dlc_cluster_common.py
----------------------
Shared helpers for running the SuperAnimal -> DeepLabCut pipeline on the
cluster via SLURM (headless, non-interactive, no GUI).

Design choices vs. the original local scripts:
  * input() prompts are replaced with argparse flags, because a batch job
    submitted with `sbatch` has no interactive stdin to answer prompts.
  * Paths point at the BeeGFS-mounted derivatives tree instead of the local
    Windows (C:\\Data\\...) / macOS (/Users/benjes/...) paths, since compute
    nodes only see the shared filesystem.
  * A single consistent derivatives layout is used everywhere:
        {data_root}/derivatives/syncdata/{subID}/{sesID}/video
        {data_root}/derivatives/dlc_superanimal/{subID}/{sesID}/{camera_view}/...
    (the original s01 wrote to a different tree than s02 read from -- fixed
    here so the pipeline is contiguous.)
  * detector defaults to the heavier fasterrcnn_resnet50_fpn_v2, since the
    cluster's GPU nodes can afford it (this replaces the old local/"tardis"
    machine-name switch, which doesn't map to anything on the cluster).
"""
import argparse
import os
import re

# Override with --data-root or the DLC_DATA_ROOT env var (e.g. set once in
# your SLURM job script / ~/.bashrc on the cluster).
DEFAULT_DATA_ROOT = os.environ.get("DLC_DATA_ROOT", "/mnt/beegfs/home/nguyen/1223-xplo-judo/10_Data/")


def add_common_args(parser: argparse.ArgumentParser) -> argparse.ArgumentParser:
    parser.add_argument("--sub", required=True, help="Subject ID, e.g. MH9HXJ or sub-MH9HXJ")
    parser.add_argument("--ses", required=True, help="Session ID, e.g. S001 or ses-S001")
    parser.add_argument("--run", default="002", help="Run ID, e.g. 002 [default: 002]")
    parser.add_argument("--cam", choices=["s", "u"], default="s",
                         help="'s' = SideView, 'u' = UpperView [default: s]")
    parser.add_argument("--detector", choices=["mobilenet", "resnet50"], default="resnet50",
                         help="Detector backbone. Cluster GPUs default to the heavier "
                              "resnet50; use 'mobilenet' only if you need to match a "
                              "specific local run 1:1. [default: resnet50]")
    parser.add_argument("--data-root", default=DEFAULT_DATA_ROOT,
                         help=f"Root of the BeeGFS derivatives tree. [default: {DEFAULT_DATA_ROOT}]")
    parser.add_argument("--gpu", default=None,
                         help="CUDA_VISIBLE_DEVICES override, e.g. '0'. Normally leave this "
                              "unset and let SLURM's --gres=gpu binding handle it.")
    return parser


def resolve_ids(args):
    """BIDS-style ID normalization, unchanged from the local scripts."""
    subLabel = re.sub(r'^sub-', '', args.sub)
    sesLabel = re.sub(r'^ses-', '', args.ses)
    runLabel = re.sub(r'^run-', '', args.run).zfill(3)

    subID = f"sub-{subLabel}"
    sesID = f"ses-{sesLabel}"
    runID = f"run-{runLabel}"
    camera_view = "UpperView" if args.cam == "u" else "SideView"
    detector_name = ("fasterrcnn_resnet50_fpn_v2" if args.detector == "resnet50"
                      else "fasterrcnn_mobilenet_v3_large_fpn")

    print(f" -> {subID} | {sesID} | {runID} | View: {camera_view} | "
          f"Detector: {detector_name}")
    return subID, sesID, runID, camera_view, detector_name


def apply_gpu(args):
    if args.gpu is not None:
        os.environ["CUDA_VISIBLE_DEVICES"] = args.gpu


def headless_matplotlib():
    """Compute nodes have no display. Must select a non-interactive backend
    BEFORE deeplabcut (which imports matplotlib) is imported, or
    evaluate_network(plotting=True) / create_labeled_video will crash trying
    to open a window."""
    import matplotlib
    matplotlib.use("Agg")


def paths_for(data_root, subID, sesID, camera_view):
    """Central place for the derivatives layout, so every script agrees."""
    raw_video_dir = os.path.join(data_root, "derivatives", "syncdata", subID, sesID, "video")
    dlc_root = os.path.join(data_root, "derivatives", "dlc_superanimal", subID, sesID, camera_view)
    zeroshot_dir = os.path.join(dlc_root, "video-zeroshot")
    estimation_dir = os.path.join(dlc_root, "video-estimation")
    return {
        "raw_video_dir": raw_video_dir,
        "dlc_root": dlc_root,
        "zeroshot_dir": zeroshot_dir,
        "estimation_dir": estimation_dir,
    }
