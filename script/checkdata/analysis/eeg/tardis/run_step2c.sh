#!/bin/bash
#SBATCH --job-name=judo_bemobil_amica
#SBATCH --output=logs/bemobil_amica_%j.out
#SBATCH --error=logs/bemobil_amica_%j.err
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16GB
#SBATCH --time=12:00:00

# Input parameters passed from batch submitter
SUB_ID=${1:-"155T4T"}
SES_ID=${2:-"S001"}
TASK_NAME=${3:-"heightaffordance"}

# Ensure log directory exists
mkdir -p logs

# Load required HPC modules
. /etc/profile
module load matlab/R2023a
chmod -R +x /mnt/beegfs/home/nguyen/matlab/toolbox/EEGLAB/eeglab2026.0.0/plugins/

echo "Starting AMICA + ICLabel (step 2C) for Subject: ${SUB_ID}, Session: ${SES_ID}, Task: ${TASK_NAME}"
echo "Runs on BOTH preprocessed and preprocessed_and_rejected inputs (rejected inputs are skipped per-run if s02b hasn't been done yet)"

# Step 3: Execute AMICA + ICLabel
matlab -nodisplay -nosplash -batch "s02c_judo_bemobil_amica_and_iclabel('${SUB_ID}', '${SES_ID}', '${TASK_NAME}')"
