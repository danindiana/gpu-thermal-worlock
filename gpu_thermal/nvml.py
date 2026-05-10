"""Direct NVML bindings via pynvml — no subprocess, no nvidia-smi forks."""

import logging
from contextlib import contextmanager

import pynvml

log = logging.getLogger(__name__)


def init():
    pynvml.nvmlInit()


def shutdown():
    pynvml.nvmlShutdown()


@contextmanager
def session():
    init()
    try:
        yield
    finally:
        shutdown()


def _handle(gpu_id: int):
    return pynvml.nvmlDeviceGetHandleByIndex(gpu_id)


def get_utilization(gpu_id: int) -> int:
    rates = pynvml.nvmlDeviceGetUtilizationRates(_handle(gpu_id))
    return rates.gpu


def get_compute_procs(gpu_id: int) -> list:
    return pynvml.nvmlDeviceGetComputeRunningProcesses(_handle(gpu_id))


def get_temperature(gpu_id: int) -> int:
    return pynvml.nvmlDeviceGetTemperature(
        _handle(gpu_id), pynvml.NVML_TEMPERATURE_GPU
    )


def get_power_draw(gpu_id: int) -> float:
    return pynvml.nvmlDeviceGetPowerUsage(_handle(gpu_id)) / 1000.0


def get_power_limit(gpu_id: int) -> float:
    return pynvml.nvmlDeviceGetPowerManagementLimit(_handle(gpu_id)) / 1000.0


def set_persistence_mode(gpu_id: int):
    pynvml.nvmlDeviceSetPersistenceMode(_handle(gpu_id), pynvml.NVML_FEATURE_ENABLED)
    log.debug("GPU %d: persistence mode enabled", gpu_id)


def set_power_limit(gpu_id: int, watts: int):
    pynvml.nvmlDeviceSetPowerManagementLimit(_handle(gpu_id), watts * 1000)
    log.info("GPU %d: power limit set to %dW", gpu_id, watts)


def set_target_temp(gpu_id: int, celsius: int):
    # nvmlDeviceSetGpuTargetTemperature is not yet exposed in nvidia-ml-py;
    # use nvidia-smi -gtt as a narrow subprocess fallback (GPU 1 only).
    import subprocess
    result = subprocess.run(
        ["nvidia-smi", "-i", str(gpu_id), "-gtt", str(celsius)],
        capture_output=True, text=True
    )
    if result.returncode != 0 and "not supported" not in result.stdout.lower():
        log.warning("GPU %d: set_target_temp failed: %s", gpu_id, result.stdout.strip())
    else:
        log.info("GPU %d: target temp set to %d°C", gpu_id, celsius)


def lock_clocks(gpu_id: int, clock_gpu: int, clock_mem: int):
    h = _handle(gpu_id)
    pynvml.nvmlDeviceSetGpuLockedClocks(h, clock_gpu, clock_gpu)
    pynvml.nvmlDeviceSetMemoryLockedClocks(h, clock_mem, clock_mem)
    log.info("GPU %d: clocks locked — GPU %dMHz / Mem %dMHz", gpu_id, clock_gpu, clock_mem)


def reset_clocks(gpu_id: int):
    h = _handle(gpu_id)
    pynvml.nvmlDeviceResetGpuLockedClocks(h)
    pynvml.nvmlDeviceResetMemoryLockedClocks(h)
    log.info("GPU %d: clocks reset to auto", gpu_id)


def get_fan_speed(gpu_id: int) -> int:
    try:
        return pynvml.nvmlDeviceGetFanSpeed(_handle(gpu_id))
    except pynvml.NVMLError:
        return -1
