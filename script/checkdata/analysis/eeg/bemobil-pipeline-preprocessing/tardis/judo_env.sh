#!/bin/bash
# Shared environment for every SLURM job of the judo EEG pipeline. Sourced by the run_*.sh scripts.
#
# Change the MATLAB version or the EEGLAB location here (one place for all steps).

set -eo pipefail

MATLAB_MODULE="${MATLAB_MODULE:-matlab/R2022b}"
export JUDO_EEGLAB_ROOT="${JUDO_EEGLAB_ROOT:-/mnt/beegfs/home/nguyen/matlab/toolbox/EEGLAB/eeglab2026.0.0}"

# /etc/profile and the module system are not written for "set -u", so load them first
# shellcheck disable=SC1091
. /etc/profile
module load "${MATLAB_MODULE}"
set -u

# Jobs run in the folder they were submitted from; the MATLAB scripts must be there.
cd "${SLURM_SUBMIT_DIR:-$(pwd)}"
if [[ ! -f s00_judo_bemobil_config.m ]]; then
    echo "[judo] ERROR: s00_judo_bemobil_config.m not found in $(pwd). Submit the job from the scripts folder." >&2
    exit 1
fi

# Each job gets its own MATLAB preferences folder, so parallel jobs never write the same files.
export MATLAB_PREFDIR="${TMPDIR:-/tmp}/matlab_prefs_${SLURM_JOB_ID:-$$}"
mkdir -p "${MATLAB_PREFDIR}"

# Use exactly the CPUs SLURM gave this job for MATLAB's own computations.
JUDO_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export JUDO_THREADS

echo "[judo] $(date '+%Y-%m-%d %H:%M:%S') job ${SLURM_JOB_ID:-local} on $(hostname), ${MATLAB_MODULE}, ${JUDO_THREADS} CPU(s)"
