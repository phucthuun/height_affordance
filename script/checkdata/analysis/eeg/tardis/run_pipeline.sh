#!/bin/bash
#SBATCH --job-name=judo_bemobil
#SBATCH --output=logs/bemobil_%j.out
#SBATCH --error=logs/bemobil_%j.err
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8GB
#SBATCH --time=04:00:00

# Input parameters passed from batch submitter
SUB_ID=${1:-"155T4T"}
SES_ID=${2:-"S001"}
TASK_NAME=${3:-"heightaffordance"}

# Ensure log directory exists
mkdir -p logs

# Load required HPC modules
. /etc/profile
module load matlab

echo "Starting pipeline for Subject: ${SUB_ID}, Session: ${SES_ID}, Task: ${TASK_NAME}"

# Step 1: Execute XDF Import
matlab -nodisplay -nosplash -batch "s01_judo_bemobil_import('${SUB_ID}', '${SES_ID}', '${TASK_NAME}')"

# Step 2: Execute Preprocessing Pipeline
matlab -nodisplay -nosplash -batch "s02a_judo_bemobil_preprocess('${SUB_ID}', '${SES_ID}', '${TASK_NAME}')"