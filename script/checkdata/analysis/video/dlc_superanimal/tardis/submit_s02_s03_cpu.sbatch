#!/bin/bash
#SBATCH --job-name=dlc_qc_seed
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/s02_s03_%j.log
#SBATCH --error=logs/s02_s03_%j.err

# Usage: sbatch submit_s02_s03_cpu.sbatch <sub> <ses> <run> <cam> [experimenter]
# Runs QC ranking (s02) then, using its flagged_trials.txt, seeds outlier
# frames into a fresh DLC project (s03). Neither step touches a GPU or a
# display, so these run comfortably on the Xeon E5-2670 CPU partition.
#
# <run> is accepted for consistency with the other steps but s02/s03 always
# operate on every run's zero-shot output already written under the
# subject/session/camera_view (pooled by design -- see
# dlc_cluster_common.py). Pass "all" here.
#
# [experimenter] is optional -- who s03 records as the DLC project's
# experimenter/scorer (defaults to "Phuc" if omitted, matching s03's own
# --experimenter default). Pass your own name as the 5th argument, e.g.:
#   sbatch submit_s02_s03_cpu.sbatch MH9HXJ S001 all s Maximilian

EXPERIMENTER="${5:-Phuc}"

python s02_zero-shot-quality-control_cluster.py --sub "$1" --ses "$2" --run "$3" --cam "$4"
python s03_dlc-project-setup_cluster.py         --sub "$1" --ses "$2" --run "$3" --cam "$4" \
    --experimenter "$EXPERIMENTER"

echo "Now rsync the project folder to your local machine and run s04 (napari) there."
