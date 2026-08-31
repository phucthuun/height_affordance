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
  * RUNS ARE POOLED, NOT ISOLATED. Each subject has 5 runs and may change
    clothing (pants / judogi) between them. Pooling all runs of a
    subject/session/camera_view into a single DLC project + single trained
    model is preferable to training one model per run: (a) it multiplies
    the small hand-labeled frame set instead of shrinking it further per
    run, and (b) it forces the network to learn joint geometry rather than
    clothing-correlated shortcuts, i.e. a model that's robust to the
    subject changing outfits mid-protocol.
    Concretely: `--run` now accepts "all" (default), a single run
    (e.g. "003"), or a comma-separated list ("001,003,005"). Only s01
    (zero-shot inference, GPU) actually uses this to pick which raw videos
    to run inference on -- every downstream step (s02 QC, s03 outlier
    seeding, s05 training, s06 analysis) already operates on everything
    present under the subject/session/camera_view directory, i.e. pooled
    across whatever runs s01 has been pointed at so far. That's
    intentional now, not an oversight: don't add per-run filtering back
    into s02/s03/s05/s06 unless you specifically want per-run models.
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
    parser.add_argument("--run", default="all",
                         help="Run selection: 'all' (default, pool every run -- recommended, "
                              "see module docstring), a single run e.g. '002', or a "
                              "comma-separated list e.g. '001,003,005'. Only s01 (zero-shot "
                              "inference) uses this to choose which raw videos to process; "
                              "s02/s03/s05/s06 always operate on everything already present "
                              "for the subject/session/camera_view (i.e. pooled).")
    parser.add_argument("--cam", choices=["s", "u", "g"], default="s",
                         help="'s' = SideView, 'u' = UpperView, 'g' = GroundView [default: s]")
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
    """BIDS-style ID normalization. --run is now a *selector*, not a single
    run -- see resolve_run_ids() for turning it into a run-glob/list."""
    subLabel = re.sub(r'^sub-', '', args.sub)
    sesLabel = re.sub(r'^ses-', '', args.ses)

    subID = f"sub-{subLabel}"
    sesID = f"ses-{sesLabel}"
    
    view_map = {
        "u": "UpperView",
        "g": "GroundView",
        "s": "SideView"
    }
    camera_view = view_map.get(args.cam, "SideView")

    detector_name = ("fasterrcnn_resnet50_fpn_v2" if args.detector == "resnet50"
                      else "fasterrcnn_mobilenet_v3_large_fpn")

    print(f" -> {subID} | {sesID} | Run selection: {args.run} | View: {camera_view} | "
          f"Detector: {detector_name}")
    return subID, sesID, camera_view, detector_name

def resolve_run_ids(args):
    """Turn --run ('all' | '002' | '001,003,005') into either None (meaning
    'no run filter, glob every run') or a list of normalized runIDs like
    ['run-001', 'run-003']. Used by s01 to decide which raw videos to run
    zero-shot inference on."""
    if args.run.strip().lower() == "all":
        return None
    runLabels = [re.sub(r'^run-', '', r.strip()).zfill(3) for r in args.run.split(",") if r.strip()]
    return [f"run-{r}" for r in runLabels]


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
    """Central place for the derivatives layout, so every script agrees.
    Deliberately NOT run-scoped: runs are pooled (see module docstring)."""
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


def select_primary_individual(df):
    """Collapse a 4-level (scorer/individuals/bodyparts/coords) SuperAnimal
    output down to 3 levels (scorer/bodyparts/coords). If >1 individual
    appears (e.g. a bystander or coach in frame), keep the most confident
    one, so a stray second detection doesn't pollute QC scores (s02) or
    seeded outlier labels (s03).

    IMPORTANT: must be applied identically wherever a zero-shot .h5 is read
    (s02 scoring, s03 outlier seeding) -- previously only s03 did this,
    which meant QC confidence scores could get silently averaged across
    multiple people while outlier-seeding downstream only ever saw the
    primary individual. Keep both call sites using this shared function."""
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


def run_id_from_filename(filename):
    """Best-effort extraction of the BIDS run label from a video/h5 filename,
    for reporting only (e.g. an extra column in qc_ranking.csv) now that
    processing itself is pooled across runs."""
    m = re.search(r'(run-\d+)', filename)
    return m.group(1) if m else "unknown"
