#!/bin/bash

# Array of participants to process
PARTICIPANTS=("155T4T")
SESSION="S001"
TASK="heightaffordance"

# Convert line endings to UNIX format automatically
sed -i 's/\r$//' run_pipeline.sh submit_all.sh 2>/dev/null

for SUB in "${PARTICIPANTS[@]}"; do
    echo "Submitting SLURM job for Subject: ${SUB}"
    sbatch run_pipeline.sh "${SUB}" "${SESSION}" "${TASK}"
    
    # Pause to prevent shared cache initialization collisions on cluster nodes
    sleep 1s
done