#!/bin/bash
#SBATCH --job-name=dlc_s01_zeroshot
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=logs/s01_zeroshot_%j.log

# Usage: sbatch submit_s01_zeroshot.sbatch <sub> <ses> <run> <cam>
# e.g.:  sbatch submit_s01_zeroshot.sbatch MH9HXJ S001 002 s

module load cuda anaconda3          # adjust to your cluster's module names
source activate deeplabcut          # conda env with deeplabcut + torch(cuda) installed

python s01_zero-shot-inference_cluster.py \
    --sub "$1" --ses "$2" --run "$3" --cam "$4" \
    --detector resnet50
