#!/bin/bash
# One-time setup on tardis (rerun after installing or updating EEGLAB / AMICA):
#   - makes the AMICA binaries executable (replaces the "chmod -R +x" that every job used to run)
#   - creates the logs/ folder the SLURM jobs write to
#   - checks that the required EEGLAB plugins are installed
# Usage:  bash setup_once.sh

set -euo pipefail
cd "$(dirname "$0")"
EEGLAB_ROOT="${JUDO_EEGLAB_ROOT:-/mnt/beegfs/home/nguyen/matlab/toolbox/EEGLAB/eeglab2026.0.0}"

mkdir -p logs
echo "EEGLAB: ${EEGLAB_ROOT}"
[[ -d "${EEGLAB_ROOT}/plugins" ]] || { echo "No plugins folder in ${EEGLAB_ROOT}" >&2; exit 1; }

found=0
while IFS= read -r -d '' binary; do
    chmod u+x "${binary}"
    echo "executable: ${binary}"
    found=1
done < <(find "${EEGLAB_ROOT}/plugins" -maxdepth 2 -type f -name 'amica15*' -print0)
[[ ${found} -eq 1 ]] || echo "WARNING: no AMICA binary (amica15*) found under ${EEGLAB_ROOT}/plugins"

for plugin in bemobil amica iclabel zapline clean_rawdata firfilt dipfit xdf; do
    match=$(find "${EEGLAB_ROOT}/plugins" -mindepth 1 -maxdepth 1 -type d -iname "*${plugin}*" -print -quit)
    if [[ -n "${match}" ]]; then
        echo "plugin found: $(basename "${match}")"
    else
        echo "WARNING: no plugin folder matching '${plugin}' in ${EEGLAB_ROOT}/plugins"
    fi
done
