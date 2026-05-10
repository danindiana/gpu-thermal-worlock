# GPU Power Limit Reduction — 275W per GPU
**Session:** 2026-05-10T11:14:10-0500  
**Session dir:** `2026-05-10_111410_gpu-power-limit-275w/`  
**Machine:** worlock (AMD Ryzen 9 5950X, ASRock X570 Taichi, Linux 6.8.12)

---

## Objective

Reduce both GPU power limits from 300W → 275W each, and persist across reboots via systemd.

---

## Prior Sessions: GPU Wattage History

### 2026-05-01 — RTX 5080 Install
**Session:** `2026-05-01_123641_rtx5080-install-diagnostic/session.md`

- RTX 5080 (GPU 0) installed, default power limit: **360W** (range: 250–400W)
- RTX 3080 (GPU 1) existing card, default power limit: **340W** (range: 100–375W)
- RTX 3080 flagged as drawing 100W at idle — unusual; scheduled for investigation
- Suggested `nvidia-smi -i 1 -pl 200` as a temporary idle-power cap (not applied at the time)

### 2026-05-04 — RTX 3080 High Idle Power Investigation
**Session:** `2026-05-04_225448_rtx3080-idle-power-investigation/session.md`

**Symptom:** RTX 3080 idling at 106W (expected: 15–20W in P8)

**Root cause:** RTX 3080 was driving the 2560×1080 ultrawide via HDMI-0. Active display forces
GDDR6X memory to max clock (9501 MHz), which draws ~80–100W in the memory subsystem alone.
The 3080 minimum power limit is 100W, so 106W was the hardware floor.

**Fix applied:** Moved HDMI cable to RTX 5080. RTX 3080 dropped to P8, ~16W idle.
**Savings:** ~90W continuous = ~789 kWh/year.

**Power limiting was NOT applied** — the root cause was the display, not the TDP headroom.

### 2026-05-10 — This Session: 275W Limits (Both GPUs)
**Motivation:** Reduce power draw and heat while retaining full inference performance.
275W provides ~8% headroom reduction from 300W; inference at typical Ollama loads peaks
around 200–250W on the 5080, so 275W is not a bottleneck.

---

## GPU State Before Change

| Field | RTX 5080 (GPU 0) | RTX 3080 (GPU 1) |
|-------|-----------------|-----------------|
| Power limit (before) | 300W | 300W |
| Min power limit | **250W** | **100W** |
| Max power limit | 400W | 375W |
| Default (factory) | 360W | 340W |
| Target | **275W** | **275W** |

---

## Lessons Learned

**What went right:**
- Correct diagnosis of display-attached idle drain (2026-05-04) — the fix (cable move) saved 90W
- Session docs captured all findings for future reference

**What to avoid:**
- Never set RTX 5080 limit below **250W** (hardware minimum — driver rejects it)
- `nvidia-smi -pl` limits are **volatile** — they vanish on reboot/driver reload; always persist via systemd
- If Ollama is mid-inference when the limit drops, inference continues but the GPU will suddenly be power-constrained; it's safe but may slow generation. Setting before loading a model is cleaner.

---

## Commands Applied

```bash
# Set power limits
sudo nvidia-smi -i 0 -pl 275   # RTX 5080: 300W → 275W
sudo nvidia-smi -i 1 -pl 275   # RTX 3080: 300W → 275W

# Verify
nvidia-smi --query-gpu=index,name,power.limit,enforced.power.limit --format=csv,noheader
```

---

## Persistence: systemd Service

File: `/etc/systemd/system/nvidia-power-limit.service`

Runs at boot (after `nvidia-persistenced.service` if present), sets both GPU limits.
Enabled with `systemctl enable --now nvidia-power-limit.service`.

To change limits in the future: edit `ExecStart=` in the service file, then
`sudo systemctl daemon-reload && sudo systemctl restart nvidia-power-limit.service`.

---

## GPU State After Change

| Field | RTX 5080 (GPU 0) | RTX 3080 (GPU 1) |
|-------|-----------------|-----------------|
| Power limit (after) | **275W** | **275W** |
| Enforced power limit | **275W** | **275W** |
| Persistence | systemd `nvidia-power-limit.service` (enabled) |

---

## Status

- [x] Root cause of prior high idle identified and fixed (2026-05-04)
- [x] Power limits set to 275W on both GPUs
- [x] Systemd service created and enabled for persistence across reboots
