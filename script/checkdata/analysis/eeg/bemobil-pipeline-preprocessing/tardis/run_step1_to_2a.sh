#!/bin/bash
#SBATCH --job-name=judo_1_2a
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=6GB
#SBATCH --time=04:00:00
#
# Steps 1 (XDF import) and 2A (trimming + preprocessing) for one participant.
# Usage (from the scripts folder; logs/ must exist):  sbatch run_step1_to_2a.sh <participant> [session] [task]

SUB_ID="${1:?Usage: sbatch run_step1_to_2a.sh <participant> [session] [task]}"
SES_ID="${2:-S001}"
TASK_NAME="${3:-heightaffordance}"

# shellcheck source=judo_env.sh
source "${SLURM_SUBMIT_DIR:-.}/judo_env.sh"
echo "[judo] Steps 1 + 2A for ${SUB_ID} ${SES_ID} ${TASK_NAME}"

matlab -nodisplay -nosplash -singleCompThread -batch \
    "s01_judo_bemobil_import('${SUB_ID}', '${SES_ID}', '${TASK_NAME}')"

matlab -nodisplay -nosplash -singleCompThread -batch \
    "s02a_judo_bemobil_preprocess('${SUB_ID}', '${SES_ID}', '${TASK_NAME}')"

echo "[judo] Steps 1 + 2A finished for ${SUB_ID}"
