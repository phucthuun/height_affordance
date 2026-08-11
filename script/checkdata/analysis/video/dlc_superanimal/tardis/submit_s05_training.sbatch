#!/bin/bash
#SBATCH --job-name=dlc_s05_train
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --time=12:00:00
#SBATCH --output=logs/s05_%j.log

# Usage: sbatch submit_s05_training.sbatch <sub> <ses> <run> <cam>
# Prereq: s04 (napari refine_labels) must have been run LOCALLY and the
# corrected project folder rsynced back to BeeGFS before this job starts.
#
# <run> is accepted for consistency but training always pools labeled
# frames from every run in the project (intentional -- see s05's header
# and dlc_cluster_common.py). Pass "all" here.

module load cuda anaconda3
source activate deeplabcut

python s05_dlc-training-evaluation_cluster.py \
    --sub "$1" --ses "$2" --run "$3" --cam "$4" \
    --maxiters 20000 --displayiters 100 --saveiters 1000
