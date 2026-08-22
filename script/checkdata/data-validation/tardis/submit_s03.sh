#!/bin/bash
#SBATCH --job-name=bids_sync_slicer
#SBATCH --output=logs/sync_%j.out
#SBATCH --error=logs/sync_%j.err
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16GB
#SBATCH --time=04:00:00

# Input parameters with fallbacks
SUB_ID=${1:-"MH9HXJ"}
SES_ID=${2:-"S001"}
RUN_ID=${3:-"001"}
TASK_NAME=${4:-"heightaffordance"}
PRE_OFFSET=${5:-"3.0"}

# Define HPC storage paths
BASE_LOC="/mnt/beegfs/home/nguyen/1223-xplo-judo/10_Data/sourcedata"
DERIVATIVES_LOC="/mnt/beegfs/home/nguyen/1223-xplo-judo/10_Data/derivatives"

mkdir -p logs
echo "-Xmx24g" > java.opts
. /etc/profile
module load matlab/R2023a
# Convert line endings to UNIX format automatically
sed -i 's/\r$//' *.sh 2>/dev/null
chmod -R +x /mnt/beegfs/home/nguyen/matlab/toolbox/EEGLAB/eeglab2026.0.0/plugins/

echo "=========================================================="
echo "Starting synchronization job for:"
echo "  Subject:     ${SUB_ID}"
echo "  Session:     ${SES_ID}"
echo "  Run ID:      ${RUN_ID}"
echo "  Task:        ${TASK_NAME}"
echo "=========================================================="

# Execute headless MATLAB function without GUI/X11 popups
matlab -nodisplay -nosplash -singleCompThread -batch \
  "s03_data_sync_function('${SUB_ID}', '${SES_ID}', '${RUN_ID}', '${TASK_NAME}', '${PRE_OFFSET}', '${BASE_LOC}', '${DERIVATIVES_LOC}')"