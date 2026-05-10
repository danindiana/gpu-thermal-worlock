"""Load and expose gpu_thermal.toml configuration."""

try:
    import tomllib
except ImportError:
    import tomli as tomllib  # Python 3.10 backport
from dataclasses import dataclass, field
from pathlib import Path

CONFIG_PATH = Path(__file__).parent.parent / "gpu_thermal.toml"


@dataclass
class GpuConfig:
    id: int
    name: str
    power_eco: int
    power_perf: int
    gtt_supported: bool
    target_temp: int = 0
    clock_mem_eco: int = 0
    clock_gpu_eco: int = 0


@dataclass
class WatchdogConfig:
    poll_interval: int = 10
    idle_threshold_pct: int = 2
    idle_cycles_before_eco: int = 6


@dataclass
class AlertingConfig:
    enabled: bool = False
    temp_warn_celsius: int = 80
    webhook_url: str = ""


@dataclass
class Config:
    gpus: list[GpuConfig]
    watchdog: WatchdogConfig
    alerting: AlertingConfig

    def gpu(self, gpu_id: int) -> GpuConfig:
        for g in self.gpus:
            if g.id == gpu_id:
                return g
        raise KeyError(f"No GPU with id {gpu_id} in config")


def load(path: Path = CONFIG_PATH) -> Config:
    with open(path, "rb") as f:
        raw = tomllib.load(f)

    gpus = []
    for key, val in raw.items():
        if key == "gpu":
            for _name, gcfg in val.items():
                gpus.append(GpuConfig(**gcfg))

    wd = WatchdogConfig(**raw.get("watchdog", {}))
    al = AlertingConfig(**raw.get("alerting", {}))
    return Config(gpus=gpus, watchdog=wd, alerting=al)
