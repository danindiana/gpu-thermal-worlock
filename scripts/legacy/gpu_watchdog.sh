#!/bin/bash

# GPU Watchdog Daemon
# Automatically switches RTX 3080 between ECO and PERF modes based on load.

GPU_ID=1
CHECK_INTERVAL=10
IDLE_THRESHOLD=2
IDLE_COUNT=0
MAX_IDLE=6 # 60 seconds of idle before eco
STATE="eco"

# Get the path to the toggle script
TOGGLE_SCRIPT="$(dirname "$(readlink -f "$0")")/../gpu_power_toggle.sh"

echo "GPU Watchdog started. Monitoring GPU $GPU_ID..."

while true; do
    # Check for active compute processes on GPU 1
    LOAD=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader -i $GPU_ID | wc -l)
    
    # Check GPU utilization
    UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i $GPU_ID)

    if [ "$LOAD" -gt 0 ] || [ "$UTIL" -gt "$IDLE_THRESHOLD" ]; then
        if [ "$STATE" == "eco" ]; then
            echo "$(date): Load detected! Switching to PERFORMANCE mode."
            sudo "$TOGGLE_SCRIPT" perf
            STATE="perf"
        fi
        IDLE_COUNT=0
    else
        if [ "$STATE" == "perf" ]; then
            ((IDLE_COUNT++))
            if [ "$IDLE_COUNT" -ge "$MAX_IDLE" ]; then
                echo "$(date): GPU idle for ${IDLE_COUNT}0s. Switching to ECO mode."
                sudo "$TOGGLE_SCRIPT" eco
                STATE="eco"
                IDLE_COUNT=0
            fi
        fi
    fi

    sleep $CHECK_INTERVAL
done
