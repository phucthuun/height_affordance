# DeepLabCut 2D / SuperAnimal pipeline

Runs on **TARDIS**, LIP/MPIB's SLURM cluster. "BeeGFS" below just means the
747 TB shared storage volume attached to TARDIS (as opposed to the head
node's local disk or the 32 TB NFS software volume) — you're not
connecting to a separate system, it's the data partition on the same
cluster you SSH into. See [the TARDIS docs](https://krause.mpib.berlin/tardis-doc/introduction/index.html)
for cluster specs and login details.

## Install DLC environment on cluster

### Tardis
1. load the conda module with `module load conda`
2. create the environment: `conda create -n dlc-superanimal python=3.10 -y` (this can take a while)
4. Activate `conda activate dlc-superanimal`. 
5. Install PyTorch with GPU (CUDA 12.6) `pip install "torch==2.3.1" torchvision --index-url https://download.pytorch.org/whl/cu118`
6. Install DeepLabCut SuperAnimal `pip install "deeplabcut[modelzoo]"`
7. Go to "/mnt/beegfs/home/nguyen/.conda/envs/dlc-superanimal/lib/python3.10/site-packages/deeplabcut/modelzoo/checkpoints" --> rename file to "superanimal_humanbody_rtmpose_x.pt"

### Local PC with and without GPU
1. Install Miniforge Prompt
2. Create and activate environment in the terminal   
```bash
# Create environment
conda create -n dlc-superanimal python=3.10 -y
# Activate the environment
conda activate dlc-superanimal 
```
3. Install DLC and backends via pip
```bash
# with GPU
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu126
# without GPU
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
pip install "deeplabcut[gui,modelzoo]"
```
5. Launch DLC `python -m deeplabcut` (or choose the right environment on VS Code)


## Which step runs where

| Step | Cluster? | Job type |
|---|---|---|
| s01 zero-shot inference | ✅ | GPU |
| s02 QC ranking | ✅ | CPU |
| s03 project setup + outlier seeding | ✅ | CPU |
| **s04 refine_labels (napari)** | ❌ **local PC only** | interactive/display |
| s05 train + evaluate | ✅ | GPU |
| s06 analyze videos | ✅ | GPU (+CPU for muxing) |

**s04 cannot move to the cluster.** `deeplabcut.refine_labels()` launches
napari, which needs a live Qt event loop and a human dragging/deleting
points on screen in real time. There's no batch equivalent to "correct
mislabeled keypoints" — it's not a computation, it's manual annotation. Even
with X11 forwarding this would be painful over the network for an
interaction-heavy GUI; keep this step local.

## Workflow
To activate environment in the terminal:
```bash
cd ./1223-xplo-judo/02_Task/height_affordance/script/checkdata/analysis/video/dlc_superanimal/tardis
module load conda
conda activate dlc-superanimal
```

1. `sbatch submit_s01_zeroshot.sbatch <sub> <ses> all <cam>` — GPU. `all`
   runs zero-shot inference on **every run's** videos for that
   subject/session/camera in one job (recommended default — see "Runs are
   pooled" below). Pass a specific run (e.g. `003`) instead if you only
   need to (re-)process one.
2. `sbatch submit_s02_s03_cpu.sbatch <sub> <ses> all <cam> [experimenter]` —
   CPU, chains QC ranking + outlier seeding across all runs' zero-shot
   output, produces a fresh DLC project with `machinelabels-iter*.h5`
   seeded per flagged trial. `[experimenter]` is optional and defaults to
   `Phuc` if omitted — pass your own name as the 5th argument to have it
   recorded as the DLC project's experimenter/scorer instead, e.g.
   `sbatch submit_s02_s03_cpu.sbatch MH9HXJ S001 all s Maximilian`. Check
   the per-run flag-rate table s02 prints — it should be roughly even
   across runs (see below), not concentrated in whichever runs happen to
   use judogi vs. pants.
3. **copy the project folder to your local machine.**
4. Run `s04_dlc-data-preparation.py` locally, cell-by-cell in VS Code /
   IPython. Save each folder's corrected `CollectedData_<scorer>.h5`. 
5. **copy the corrected project folder back to tardis.**
6. `sbatch submit_s05_s06_train_analyze <sub> <ses> all <cam>` — GPU,
   `merge_datasets` → `create_training_dataset` → `train_network` →
   `evaluate_network`. Then analyzes/filters/plot trajectories/labels all videos regardless of runs.

## Some explanations

-**Runs are pooled, not trained separately**

Each subject has 5 runs and may change clothing (no judo pants in some runs, a
judogi in others). 
- SuperAnimal's zero-shot + video-adaptation step (s01) already re-adapts
  per video, so clothing differences are handled at that stage regardless
  of pooling.
- Fine-tuning (s05) benefits from pooling because (a) the hand-corrected
  frame set from s04 is small — splitting it 5 ways starves each per-run
  model of data — and (b) training on frames spanning multiple clothing
  conditions forces the network to key off body geometry rather than
  clothing-correlated shortcuts (e.g. "wrist = sleeve cuff"), which is
  exactly the robustness you want across a clothing change mid-protocol.

Concretely: `--run` accepts `all` (default), a single run (`003`), or a
comma-separated list (`001,003,005`). Only **s01** uses it to choose which
raw videos to run inference on. s02, s03, s05, and s06 always operate on
everything already present for the subject/session/camera_view — i.e.
pooled across every run s01 has been pointed at, regardless of what
`--run` you pass to them. Pass `all` there for clarity; it's accepted but
ignored.

- **Paths**: Root is save in dlc_cluster_common.py / --data-root / $DLC_DATA_ROOT, 
default /mnt/beegfs/home/nguyen/1223-xplo-judo/10_Data/ — change this to your actual mount point. Layout is unified across all steps as:
  ```
  unlabeled video : {data_root}/derivatives/syncdata/{subID}/{sesID}/video
  zeroshot video  : {data_root}/derivatives/dlc_superanimal/{subID}/{sesID}/{camera_view}/video-zeroshot
  estimated video : {data_root}/derivatives/dlc_superanimal/{subID}/{sesID}/{camera_view}/video-estimation
  dlc project     : {data_root}/derivatives/dlc_superanimal/{subID}/{sesID}/{camera_view}/heightaffordance-*/
  ```

- **Detector defaults to `fasterrcnn_resnet50_fpn_v2`** (the old
  `local`/`tardis` machine-name switch doesn't mean anything on a shared
  cluster; the GPU nodes can afford the heavier detector, override with
  `--detector mobilenet` if you need to match a specific earlier run).
- **Headless matplotlib.** `matplotlib.use("Agg")` is forced before
  `deeplabcut` is imported in s01/s05/s06, since `evaluate_network(plotting=True)`
  and `create_labeled_video` will otherwise try to open a window that
  doesn't exist on a compute node.
- **`--gpu`** lets you pin `CUDA_VISIBLE_DEVICES` manually if you're not
  relying on `--gres=gpu` binding alone.
- Use `opencv-python-headless` (not `opencv-python`) in the cluster conda
  env for s03 — avoids pulling in a Qt dependency the compute node can't use.
- **`--experimenter` is exposed on `submit_s02_s03_cpu.sbatch`.** s03 takes
  `--experimenter` (defaults to `"Phuc"`); the sbatch wrapper now accepts it
  as an optional 5th positional argument and forwards it to s03 only (s02
  has no such flag). Omit it to keep the default.

## Sizing notes for your hardware

- GPU jobs (s01, s05, s06) are the ones worth scheduling on your 7 GPU
  nodes (24 GPUs total) — `--gres=gpu:1` per job is enough for a single
  subject/session/run; DLC/SuperAnimal doesn't multi-GPU out of the box.
- CPU jobs (s02, s03) are cheap; the Xeon E5-2670 nodes (no AVX-512, no HT)
  are fine for pandas/HDF5/OpenCV work at this scale — don't burn a GPU
  allocation on them.
- 747 TB BeeGFS (TARDIS's attached shared storage — see note at the top) is
  where all `derivatives/` should live; keep raw video there too so
  compute nodes don't need to pull data over the network from elsewhere.
