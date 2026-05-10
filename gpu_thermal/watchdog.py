"""GPU watchdog daemon — replaces gpu_watchdog.sh.

Monitors GPU utilization and switches between eco/perf modes automatically.
Runs as a systemd Type=simple service under root.
"""

import logging
import signal
import sys
import time
from enum import Enum, auto

import pynvml
import sdnotify

from gpu_thermal import nvml
from gpu_thermal.config import load as load_config
from gpu_thermal.modes import apply_eco, apply_perf

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger("gpu-watchdog")


class State(Enum):
    ECO = auto()
    PERF = auto()


class Watchdog:
    def __init__(self, cfg, notifier):
        self.cfg = cfg
        self.notifier = notifier
        self.state = State.ECO
        self.idle_count = 0
        self._running = True
        self._monitor_gpu_id = 1  # RTX 3080 — load-bearing GPU for inference

        signal.signal(signal.SIGTERM, self._handle_sigterm)
        signal.signal(signal.SIGHUP, self._handle_sighup)

    def _handle_sigterm(self, signum, frame):
        log.info("SIGTERM received — applying eco mode and shutting down.")
        try:
            apply_eco(self.cfg)
        except Exception as e:
            log.warning("Could not apply eco on shutdown: %s", e)
        self._running = False

    def _handle_sighup(self, signum, frame):
        log.info("SIGHUP received — reloading config.")
        try:
            self.cfg = load_config()
            log.info("Config reloaded.")
        except Exception as e:
            log.warning("Config reload failed: %s", e)

    def _is_loaded(self) -> bool:
        try:
            procs = nvml.get_compute_procs(self._monitor_gpu_id)
            util = nvml.get_utilization(self._monitor_gpu_id)
            return len(procs) > 0 or util > self.cfg.watchdog.idle_threshold_pct
        except pynvml.NVMLError as e:
            log.warning("NVML error during load check: %s", e)
            return False

    def _log_status(self):
        try:
            for gpu in self.cfg.gpus:
                temp = nvml.get_temperature(gpu.id)
                power = nvml.get_power_draw(gpu.id)
                fan = nvml.get_fan_speed(gpu.id)
                fan_str = f"{fan}%" if fan >= 0 else "N/A"
                log.info(
                    "%s: %d°C  %.0fW  fan:%s  [%s]",
                    gpu.name, temp, power, fan_str, self.state.name
                )
                if self.cfg.alerting.enabled and temp >= self.cfg.alerting.temp_warn_celsius:
                    log.warning(
                        "TEMP ALERT: %s at %d°C (threshold %d°C)",
                        gpu.name, temp, self.cfg.alerting.temp_warn_celsius
                    )
        except pynvml.NVMLError as e:
            log.warning("NVML error during status log: %s", e)

    def run(self):
        log.info("GPU Watchdog started. Monitoring GPU %d.", self._monitor_gpu_id)
        apply_eco(self.cfg)
        self.notifier.notify("READY=1")

        while self._running:
            loaded = self._is_loaded()

            if loaded:
                if self.state is State.ECO:
                    log.info("Load detected — switching to PERF mode.")
                    apply_perf(self.cfg)
                    self.state = State.PERF
                self.idle_count = 0
            else:
                if self.state is State.PERF:
                    self.idle_count += 1
                    cycles_needed = self.cfg.watchdog.idle_cycles_before_eco
                    log.debug(
                        "Idle cycle %d/%d before ECO switch.",
                        self.idle_count, cycles_needed
                    )
                    if self.idle_count >= cycles_needed:
                        log.info(
                            "GPU idle for %ds — switching to ECO mode.",
                            self.idle_count * self.cfg.watchdog.poll_interval,
                        )
                        apply_eco(self.cfg)
                        self.state = State.ECO
                        self.idle_count = 0

            self._log_status()
            self.notifier.notify("WATCHDOG=1")
            time.sleep(self.cfg.watchdog.poll_interval)

        log.info("Watchdog stopped.")


def main():
    cfg = load_config()
    notifier = sdnotify.SystemdNotifier()

    with nvml.session():
        try:
            watchdog = Watchdog(cfg, notifier)
            watchdog.run()
        except pynvml.NVMLError as e:
            log.error("Fatal NVML error: %s", e)
            sys.exit(1)
        except KeyboardInterrupt:
            log.info("Interrupted.")


if __name__ == "__main__":
    main()
