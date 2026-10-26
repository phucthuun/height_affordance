#!/bin/bash
# Submit step 2C for every participant in a list, one SLURM job each.
#
# Usage:  bash submit_step2c.sh [participants_file] [mode]
#   participants_file  one ID per line, # starts a comment (default: participants_step2c.txt)
#   mode               auto | manualauto (default: both)

set -euo pipefail
cd "$(dirname "$0")"

SESSION="S001"
TASK="heightaffordance"
LIST="${1:-participants_step2c.txt}"
MODE="${2:-}"
[[ -f "${LIST}" ]] || { echo "Participant list not found: ${LIST}" >&2; exit 1; }

mkdir -p logs
sed -i 's/\r$//' ./*.sh "${LIST}" 2>/dev/null || true

while IFS= read -r line || [[ -n "${line}" ]]; do
    SUB="${line%%#*}"
    SUB="$(echo "${SUB}" | tr -d '[:space:]')"
    [[ -z "${SUB}" ]] && continue
    JOB=$(sbatch --parsable run_step2c.sh "${SUB}" "${SESSION}" "${TASK}" ${MODE:+"${MODE}"})
    echo "Step 2C (${MODE:-both modes}) for ${SUB}: job ${JOB}"
done < "${LIST}"
