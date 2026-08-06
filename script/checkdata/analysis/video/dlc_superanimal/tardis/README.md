# DeepLabCut 2D / SuperAnimal pipeline

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
`cd ./1223-xplo-judo/02_Task/height_affordance/script/checkdata/analysis/video/dlc_superanimal/tardis`
`module load conda`
`conda activate dlc-superanimal`

1. `sbatch submit_s01_zeroshot.sbatch <sub> <ses> <run> <cam>` — GPU
2. `sbatch submit_s02_s03_cpu.sbatch <sub> <ses> <run> <cam>` — CPU, chains
   QC ranking + outlier seeding, produces a fresh DLC project with
   `machinelabels-iter*.h5` seeded per flagged trial.
3. **rsync the project folder to your local machine.**
4. Run `s04_dlc-data-preparation.py` locally, cell-by-cell in VS Code /
   IPython (unchanged — still needs a live Qt loop). Save each folder's
   corrected `CollectedData_<scorer>.h5`.
5. **rsync the corrected project folder back to BeeGFS.**
6. `sbatch submit_s05_training.sbatch <sub> <ses> <run> <cam>` — GPU,
   `merge_datasets` → `create_training_dataset` → `train_network` →
   `evaluate_network`.
7. `sbatch submit_s06_analysis.sbatch <sub> <ses> <run> <cam>` — GPU,
   analyzes/filters/labels the full video set.

## What changed vs. the original local scripts

- **No `input()` prompts.** SLURM batch jobs have no interactive stdin, so
  every script now takes `argparse` flags (`--sub`, `--ses`, `--run`,
  `--cam`, `--detector`, `--data-root`, `--gpu`). Defaults match the
  originals (`run=002`, `cam=s`).
- **Paths point at BeeGFS**, not `C:\Data\Research\...` or
  `/Users/benjes/Desktop/...`. Root is `--data-root` /
  `$DLC_DATA_ROOT`, default `/beegfs/data/Research/10_Data` — change this to
  your actual mount point. Layout is unified across all steps as:
  ```
  {data_root}/derivatives/syncdata/{subID}/{sesID}/video
  {data_root}/derivatives/dlc_superanimal/{subID}/{sesID}/{camera_view}/video-zeroshot
  {data_root}/derivatives/dlc_superanimal/{subID}/{sesID}/{camera_view}/video-estimation
  {data_root}/derivatives/dlc_superanimal/{subID}/{sesID}/{camera_view}/heightaffordance-*/
  ```
  (this also fixes a mismatch in the originals: local s01 wrote zero-shot
  output under the raw-video tree, but s02 read it from the
  `dlc_superanimal` derivatives tree — those didn't line up.)
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

## Sizing notes for your hardware

- GPU jobs (s01, s05, s06) are the ones worth scheduling on your 7 GPU
  nodes (24 GPUs total) — `--gres=gpu:1` per job is enough for a single
  subject/session/run; DLC/SuperAnimal doesn't multi-GPU out of the box.
- CPU jobs (s02, s03) are cheap; the Xeon E5-2670 nodes (no AVX-512, no HT)
  are fine for pandas/HDF5/OpenCV work at this scale — don't burn a GPU
  allocation on them.
- 747 TB BeeGFS is where all `derivatives/` should live; keep raw video on
  BeeGFS too so compute nodes don't need to pull data over the network from
  elsewhere.
