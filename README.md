# gpu-thermal-worlock

GPU thermal management configuration for the **worlock** machine — dual NVIDIA RTX 5080 + RTX 3080.

**Host:** worlock · Ubuntu/Debian · Linux 6.8.12  
**Date:** 2026-05-10  
**Driver:** 580.142 · CUDA 13.0

---

## Hardware

| Slot | GPU | Architecture | VRAM | Default TDP | Power Range |
|------|-----|-------------|------|-------------|-------------|
| GPU 0 | RTX 5080 | Blackwell | ~16 GB | 360 W | 250–400 W |
| GPU 1 | RTX 3080 | Ampere | ~10 GB | 340 W | 100–375 W |

---

## Thermal Configuration

| Setting | RTX 5080 (GPU 0) | RTX 3080 (GPU 1) |
|---------|-----------------|-----------------|
| Target Temp (`-gtt`) | Not supported (Blackwell) | **70°C** (range 65–91°C) |
| Power cap — eco | **300 W** | **300 W** |
| Power cap — perf | **300 W** | **300 W** |
| Slowdown threshold | T.Limit offset -2°C | 95°C |
| Shutdown threshold | T.Limit offset -5°C | 98°C |
| Margin to slowdown | N/A | 25°C |

---

## How It Works

1. **`gpu-eco-mode.service`** runs at boot (after `nvidia-persistenced`) and calls `gpu_power_toggle.sh eco` to apply all thermal settings.
2. **`gpu-watchdog.service`** monitors GPU 1 utilization every 10 seconds and calls `gpu_power_toggle.sh perf` under load, `eco` after 60s idle — both modes enforce the 300W caps.
3. Settings applied by `nvidia-smi` do not survive driver reloads without persistence mode and the systemd service.

---

## Repository Layout

```
gpu-thermal-worlock/
├── README.md
├── scripts/
│   ├── gpu_power_toggle.sh   # eco/perf toggle — edit power limits and target temps here
│   └── gpu_watchdog.sh       # watchdog daemon — load detection and mode switching
├── systemd/
│   ├── gpu-eco-mode.service  # oneshot: apply thermal settings at boot
│   └── gpu-watchdog.service  # daemon: auto eco/perf switching based on GPU load
└── docs/
    ├── 2026-05-10_gpu_thermal_management.md       # full session log
    ├── 2026-05-10_gpu_thermal_lessons_learned.md  # 6 key findings
    ├── 2026-05-10_gpu_thermal_lessons_learned.{dot,png,svg}
    ├── 2026-05-10_gpu_thermal_howto.md            # command reference & workflow
    ├── 2026-05-10_gpu_thermal_howto.{dot,png,svg}
    ├── 2026-05-10_gpu_thermal_future_directions.md  # roadmap
    └── 2026-05-10_gpu_thermal_future_directions.{dot,png,svg}
```

---

## Quick Reference

```bash
# Apply eco mode now (300W caps, 3080 target temp 70°C, locked clocks)
sudo ./scripts/gpu_power_toggle.sh eco

# Apply perf mode now (300W caps, 3080 target temp 70°C, auto clocks)
sudo ./scripts/gpu_power_toggle.sh perf

# Reload boot-time thermal settings
sudo systemctl restart gpu-eco-mode.service

# Check current temps and power
nvidia-smi --query-gpu=index,name,temperature.gpu,power.draw,power.limit,fan.speed \
  --format=csv,noheader

# Check watchdog activity
journalctl -u gpu-watchdog.service -n 30 --no-pager
```

---

## Diagrams

| Document | PNG | SVG |
|----------|-----|-----|
| Lessons Learned | [png](docs/2026-05-10_gpu_thermal_lessons_learned.png) | [svg](docs/2026-05-10_gpu_thermal_lessons_learned.svg) |
| How-To Workflow | [png](docs/2026-05-10_gpu_thermal_howto.png) | [svg](docs/2026-05-10_gpu_thermal_howto.svg) |
| Future Directions | [png](docs/2026-05-10_gpu_thermal_future_directions.png) | [svg](docs/2026-05-10_gpu_thermal_future_directions.svg) |
