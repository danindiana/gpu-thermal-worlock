"""Eco and perf mode application logic."""

import logging
from gpu_thermal import nvml
from gpu_thermal.config import Config

log = logging.getLogger(__name__)


def apply_eco(cfg: Config):
    log.info("Applying ECO mode")
    for gpu in cfg.gpus:
        nvml.set_persistence_mode(gpu.id)
        nvml.set_power_limit(gpu.id, gpu.power_eco)
        if gpu.gtt_supported and gpu.target_temp:
            nvml.set_target_temp(gpu.id, gpu.target_temp)
        if gpu.clock_gpu_eco and gpu.clock_mem_eco:
            nvml.lock_clocks(gpu.id, gpu.clock_gpu_eco, gpu.clock_mem_eco)
        log.info(
            "%s: ECO — %dW cap%s%s",
            gpu.name,
            gpu.power_eco,
            f", target {gpu.target_temp}°C" if gpu.gtt_supported else "",
            f", clocks locked {gpu.clock_gpu_eco}/{gpu.clock_mem_eco}MHz"
            if gpu.clock_gpu_eco else "",
        )


def apply_perf(cfg: Config):
    log.info("Applying PERF mode")
    for gpu in cfg.gpus:
        nvml.set_persistence_mode(gpu.id)
        nvml.set_power_limit(gpu.id, gpu.power_perf)
        if gpu.gtt_supported and gpu.target_temp:
            nvml.set_target_temp(gpu.id, gpu.target_temp)
        if gpu.clock_gpu_eco:
            nvml.reset_clocks(gpu.id)
        log.info(
            "%s: PERF — %dW cap%s, clocks auto",
            gpu.name,
            gpu.power_perf,
            f", target {gpu.target_temp}°C" if gpu.gtt_supported else "",
        )
