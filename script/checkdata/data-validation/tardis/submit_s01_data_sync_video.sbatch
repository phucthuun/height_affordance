#!/bin/bash
#SBATCH --job-name=bids_video_sync
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=logs/s00_sync_%j.log
#SBATCH --error=logs/s00_sync_%j.err

# Load Conda module
module load conda

# Initialize Conda shell functions inside the SLURM subshell
eval "$(conda shell.bash hook)"

# Activate your target environment
conda activate dlc-superanimal

SUB="$1"
SES="$2"
RUN="${3:-all}"
TASK="${4:-heightaffordance}"

python s01_data_sync_video.py \
    --sub "$SUB" \
    --ses "$SES" \
    --run "$RUN" \
    --task "$TASK"