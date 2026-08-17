#!/bin/bash
#SBATCH --job-name=dlc_s05_train_s06_analyze
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=6:00:00
#SBATCH --output=logs/s05_s06_%j.log

# Usage: sbatch submit_s05_s06_train_analyze.sbatch <sub> <ses> <run> <cam>
# Prereq: s04 (napari refine_labels) must have been run LOCALLY and the
# corrected project folder rsynced back to BeeGFS before this job starts.
#
# <run> is accepted for consistency but training and analyzing always run
under the subject/session/camera_view regardless of run. Pass "all" here.

module load cuda anaconda3
source activate deeplabcut

python s05_dlc-training-evaluation_cluster.py \
    --sub "$1" --ses "$2" --run "$3" --cam "$4" \
    --maxiters 20000 --displayiters 100 --saveiters 1000


python s06_dlc-analysis_cluster.py --sub "$1" --ses "$2" --run "$3" --cam "$4"
