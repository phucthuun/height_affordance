#!/bin/bash

# Array of participants to process
PARTICIPANTS=("155T4T" "LINN00" "K2DJJ8" "MH9HXJ")
SESSION="S001"
TASK="heightaffordance"

# Ensure the logs directory exists BEFORE submitting
mkdir -p logs

# Convert line endings to UNIX format automatically
sed -i 's/\r$//' *.sh 2>/dev/null

for SUB in "${PARTICIPANTS[@]}"; do
    echo "Submitting SLURM job for Subject: ${SUB}"
    sbatch run_step1_to_2a.sh "${SUB}" "${SESSION}" "${TASK}"
    
    # Pause to prevent shared cache initialization collisions on cluster nodes
    sleep 1s
done
