"""CLI entry point — replaces gpu_power_toggle.sh.

Usage:
    python3 -m gpu_thermal.cli eco
    python3 -m gpu_thermal.cli perf
"""

import logging
import sys

from gpu_thermal import nvml
from gpu_thermal.config import load as load_config
from gpu_thermal.modes import apply_eco, apply_perf

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("eco", "perf"):
        print("Usage: python3 -m gpu_thermal.cli [eco|perf]", file=sys.stderr)
        sys.exit(1)

    mode = sys.argv[1]
    cfg = load_config()

    with nvml.session():
        if mode == "eco":
            apply_eco(cfg)
        else:
            apply_perf(cfg)

    log.info("Mode '%s' applied successfully.", mode)


if __name__ == "__main__":
    main()
