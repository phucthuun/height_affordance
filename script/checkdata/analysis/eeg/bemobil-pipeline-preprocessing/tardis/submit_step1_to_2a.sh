#!/bin/bash
# Submit steps 1 + 2A for every participant in a list, one SLURM job each.
#
# Usage:  bash submit_step1_to_2a.sh [participants_file] [--then-2c]
#   participants_file  one ID per line, # starts a comment (default: participants_step1_to_2a.txt)
#   --then-2c          also queue step 2C (mode "auto") to start after each job succeeds

set -euo pipefail
cd "$(dirname "$0")"

SESSION="S001"
TASK="heightaffordance"
LIST="participants_step1_to_2a.txt"
THEN_2C=0
for arg in "$@"; do
    case "${arg}" in
        --then-2c) THEN_2C=1 ;;
        *) LIST="${arg}" ;;
    esac
done
[[ -f "${LIST}" ]] || { echo "Participant list not found: ${LIST}" >&2; exit 1; }

mkdir -p logs                                   # SLURM writes the logs there; it must exist before sbatch
sed -i 's/\r$//' ./*.sh "${LIST}" 2>/dev/null || true   # files edited on Windows

while IFS= read -r line || [[ -n "${line}" ]]; do
    SUB="${line%%#*}"
    SUB="$(echo "${SUB}" | tr -d '[:space:]')"
    [[ -z "${SUB}" ]] && continue
    JOB=$(sbatch --parsable run_step1_to_2a.sh "${SUB}" "${SESSION}" "${TASK}")
    echo "Steps 1 + 2A for ${SUB}: job ${JOB}"
    if [[ ${THEN_2C} -eq 1 ]]; then
        JOB2=$(sbatch --parsable --dependency=afterok:"${JOB}" run_step2c.sh "${SUB}" "${SESSION}" "${TASK}" auto)
        echo "  step 2C (auto) for ${SUB} queued after it: job ${JOB2}"
    fi
done < "${LIST}"
