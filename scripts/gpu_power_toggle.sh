#!/bin/bash

# GPU Power Management Toggle Script
# GPU 1 = RTX 3080 (Ampere, supports -gtt target temp)
# GPU 0 = RTX 5080 (Blackwell, no -gtt support; thermal managed via power cap)

GPU_ID=1
GPU_ID_5080=0

# RTX 5080: cap power to reduce thermals (default 360W, range 250-400W)
RTX5080_ECO_POWER=300
RTX5080_PERF_POWER=300

# RTX 3080: cap power to reduce thermals (default 340W, range 100-375W)
RTX3080_ECO_POWER=300
RTX3080_PERF_POWER=300

if [ "$1" == "eco" ]; then
    echo "Switching to ECO mode..."
    sudo nvidia-smi -pm 1 -i $GPU_ID
    sudo nvidia-smi -pl $RTX3080_ECO_POWER -i $GPU_ID
    sudo nvidia-smi -lmc 405 -i $GPU_ID
    sudo nvidia-smi -lgc 210 -i $GPU_ID
    sudo nvidia-smi -i $GPU_ID -gtt 70
    echo "RTX 3080 ECO mode active (~44W idle, target temp 70°C, power cap ${RTX3080_ECO_POWER}W)."
    sudo nvidia-smi -pm 1 -i $GPU_ID_5080
    sudo nvidia-smi -pl $RTX5080_ECO_POWER -i $GPU_ID_5080
    echo "RTX 5080 power capped to ${RTX5080_ECO_POWER}W (thermal reduction, no -gtt support)."
elif [ "$1" == "perf" ]; then
    echo "Switching to PERFORMANCE mode..."
    sudo nvidia-smi -pm 1 -i $GPU_ID
    sudo nvidia-smi -pl $RTX3080_PERF_POWER -i $GPU_ID
    sudo nvidia-smi -rmc -i $GPU_ID
    sudo nvidia-smi -rgc -i $GPU_ID
    sudo nvidia-smi -i $GPU_ID -gtt 70
    echo "RTX 3080 PERFORMANCE mode active (auto clocks, target temp 70°C, power limit ${RTX3080_PERF_POWER}W)."
    sudo nvidia-smi -pm 1 -i $GPU_ID_5080
    sudo nvidia-smi -pl $RTX5080_PERF_POWER -i $GPU_ID_5080
    echo "RTX 5080 power limit ${RTX5080_PERF_POWER}W (default)."
else
    echo "Usage: $0 [eco|perf]"
fi
