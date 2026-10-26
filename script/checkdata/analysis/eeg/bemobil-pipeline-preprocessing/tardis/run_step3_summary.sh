#!/bin/bash
#SBATCH --job-name=judo_3_summary
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2GB
#SBATCH --time=00:30:00
#
# Step 3: group QC table and methods-text draft from all per-run QC files.
# Usage (from the scripts folder):  sbatch run_step3_summary.sh [task]

TASK_NAME="${1:-heightaffordance}"

# shellcheck source=judo_env.sh
source "${SLURM_SUBMIT_DIR:-.}/judo_env.sh"
matlab -nodisplay -nosplash -singleCompThread -batch "s03_judo_qc_summary_and_methods('${TASK_NAME}')"
