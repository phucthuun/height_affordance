#!/bin/bash
#SBATCH --job-name=dlc_s01_zeroshot
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=12:00:00              # bumped up: --run all now processes all 5 runs' videos in one job
#SBATCH --output=logs/s01_zeroshot_%j.log

# Usage: sbatch submit_s01_zeroshot.sbatch <sub> <ses> <run> <cam>
# <run> is "all" (recommended -- processes all 5 runs' videos in this one
# GPU job, since downstream QC/training pool across runs anyway), a single
# run e.g. "002", or a comma-separated list e.g. "001,003,005".
# e.g.:  sbatch submit_s01_zeroshot.sbatch MH9HXJ S001 all s
#        sbatch submit_s01_zeroshot.sbatch MH9HXJ S001 003 s   # re-run just run 3

module load cuda anaconda3          # adjust to your cluster's module names
source activate deeplabcut          # conda env with deeplabcut + torch(cuda) installed

python s01_zero-shot-inference_cluster.py \
    --sub "$1" --ses "$2" --run "$3" --cam "$4" \
    --detector resnet50
