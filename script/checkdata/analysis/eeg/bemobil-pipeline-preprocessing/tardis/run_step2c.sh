#!/bin/bash
#SBATCH --job-name=judo_2c
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16GB
#SBATCH --time=12:00:00
#
# Step 2C (AMICA, dipole fitting, ICLabel cleaning, QC report) for one participant.
# Usage (from the scripts folder; logs/ must exist):
#   sbatch run_step2c.sh <participant> [session] [task] [mode]
# mode: auto | manualauto | empty for both. --cpus-per-task should match bemobil_config.max_threads (4).
# A job that hits the time limit can simply be resubmitted: finished AMICA results are reused.

SUB_ID="${1:?Usage: sbatch run_step2c.sh <participant> [session] [task] [mode]}"
SES_ID="${2:-S001}"
TASK_NAME="${3:-heightaffordance}"
MODE="${4:-}"

# shellcheck source=judo_env.sh
source "${SLURM_SUBMIT_DIR:-.}/judo_env.sh"
echo "[judo] Step 2C for ${SUB_ID} ${SES_ID} ${TASK_NAME} mode(s): ${MODE:-all}"

if [[ -n "${MODE}" ]]; then
    CALL="s02c_judo_bemobil_amica_and_iclabel('${SUB_ID}', '${SES_ID}', '${TASK_NAME}', '${MODE}')"
else
    CALL="s02c_judo_bemobil_amica_and_iclabel('${SUB_ID}', '${SES_ID}', '${TASK_NAME}')"
fi
matlab -nodisplay -nosplash -batch "maxNumCompThreads(${JUDO_THREADS}); ${CALL}"

echo "[judo] Step 2C finished for ${SUB_ID}"
