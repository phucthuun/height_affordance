#!/bin/bash
#SBATCH --job-name=dlc_qc_seed
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/s02_s03_%j.log

# Usage: sbatch submit_s02_s03_cpu.sbatch <sub> <ses> <run> <cam>
# Runs QC ranking (s02) then, using its flagged_trials.txt, seeds outlier
# frames into a fresh DLC project (s03). Neither step touches a GPU or a
# display, so these run comfortably on the Xeon E5-2670 CPU partition.

module load anaconda3
source activate deeplabcut

python s02_zero-shot-quality-control_cluster.py --sub "$1" --ses "$2" --run "$3" --cam "$4"
python s03_dlc-project-setup_cluster.py         --sub "$1" --ses "$2" --run "$3" --cam "$4"

echo "Now rsync the project folder to your local machine and run s04 (napari) there."
