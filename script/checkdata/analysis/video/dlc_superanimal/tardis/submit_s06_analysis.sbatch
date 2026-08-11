#!/bin/bash
#SBATCH --job-name=dlc_s06_analyze
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=06:00:00
#SBATCH --output=logs/s06_%j.log

# Usage: sbatch submit_s06_analysis.sbatch <sub> <ses> <run> <cam>
# <run> is accepted for consistency but s06 already analyzes every video
# under the subject/session/camera_view regardless of run. Pass "all".

module load cuda anaconda3
source activate deeplabcut

python s06_dlc-analysis_cluster.py --sub "$1" --ses "$2" --run "$3" --cam "$4"
