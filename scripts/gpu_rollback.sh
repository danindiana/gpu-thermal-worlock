#!/usr/bin/env bash
# gpu_rollback.sh — interactive power-limit rollback wizard for worlock dual-GPU system
# Restores GPU 0 (RTX 5080) and GPU 1 (RTX 3080) to a known-good prior state.
# Supports: custom value, known checkpoints, or full factory reset.

set -euo pipefail

# ── Color palette (matches the dark-neon theme) ──────────────────────────────
RED='\033[0;31m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Hardware limits (RTX 5080: min 250W, max 400W; RTX 3080: min 100W, max 375W) ─
GPU0_MIN=250; GPU0_MAX=400; GPU0_FACTORY=360
GPU1_MIN=100; GPU1_MAX=375; GPU1_FACTORY=340

# ── Known checkpoints (newest first) ─────────────────────────────────────────
# Format: "LABEL|GPU0_W|GPU1_W|DATE|NOTES"
CHECKPOINTS=(
    "Current (275W each)|275|275|2026-05-10|nvidia-power-limit.service + gpu-eco-mode.service"
    "Initial cap (300W each)|300|300|2026-05-10|gpu-eco-mode.service first deployment"
    "Factory defaults|360|340|2026-05-01|RTX 5080 install — CMOS reset baseline"
    "Custom value|||now|Enter your own wattage for each GPU"
)

# ── Helpers ───────────────────────────────────────────────────────────────────
banner() {
    echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗"
    echo -e "║        GPU Power Limit Rollback Wizard               ║"
    echo -e "╚══════════════════════════════════════════════════════╝${RESET}"
}

current_state() {
    echo -e "\n${BOLD}Current GPU State:${RESET}"
    nvidia-smi --query-gpu=index,name,power.draw,power.limit,enforced.power.limit,clocks.current.graphics,clocks.current.memory \
        --format=csv,noheader 2>/dev/null | \
    awk -F', ' '{
        printf "  GPU %s  %-25s  draw=%-8s  limit=%-8s  enforced=%-8s  clk=%s/%s\n",
               $1, $2, $3, $4, $5, $6, $7
    }' || echo -e "  ${RED}nvidia-smi not available${RESET}"

    echo ""
    systemctl is-active --quiet nvidia-power-limit.service 2>/dev/null && \
        echo -e "  ${GREEN}nvidia-power-limit.service: active${RESET}" || \
        echo -e "  ${YELLOW}nvidia-power-limit.service: not active${RESET}"
    systemctl is-active --quiet gpu-eco-mode.service 2>/dev/null && \
        echo -e "  ${GREEN}gpu-eco-mode.service: active (exited)${RESET}" || \
        echo -e "  ${YELLOW}gpu-eco-mode.service: not active${RESET}"
}

apply_limits() {
    local g0=$1 g1=$2

    # Validate ranges
    if (( g0 < GPU0_MIN || g0 > GPU0_MAX )); then
        echo -e "${RED}ERROR: GPU 0 value ${g0}W out of range [${GPU0_MIN}–${GPU0_MAX}W]${RESET}" >&2
        exit 1
    fi
    if (( g1 < GPU1_MIN || g1 > GPU1_MAX )); then
        echo -e "${RED}ERROR: GPU 1 value ${g1}W out of range [${GPU1_MIN}–${GPU1_MAX}W]${RESET}" >&2
        exit 1
    fi

    echo -e "\n${YELLOW}Applying: GPU 0 → ${g0}W, GPU 1 → ${g1}W${RESET}"
    sudo nvidia-smi -i 0 -pl "$g0"
    sudo nvidia-smi -i 1 -pl "$g1"
    echo -e "${GREEN}Power limits applied.${RESET}"
}

persist_service() {
    local g0=$1 g1=$2

    echo -e "\n${BOLD}Persist limits across reboots?${RESET}"
    echo "  This will update /etc/systemd/system/nvidia-power-limit.service"
    printf "  to set GPU 0=%dW and GPU 1=%dW at every boot.\n" "$g0" "$g1"
    echo -e "  ${YELLOW}[y/N]${RESET} "
    read -r ans
    if [[ "${ans,,}" == "y" ]]; then
        sudo tee /etc/systemd/system/nvidia-power-limit.service > /dev/null << EOF
[Unit]
Description=NVIDIA GPU power limit enforcement (RTX5080=${g0}W, RTX3080=${g1}W)
After=multi-user.target
After=nvidia-persistenced.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'nvidia-smi -i 0 -pl ${g0} && nvidia-smi -i 1 -pl ${g1}'

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        echo -e "${GREEN}nvidia-power-limit.service updated and reloaded.${RESET}"
    else
        echo -e "${YELLOW}Skipping persistence — limits will reset on next reboot.${RESET}"
    fi
}

verify_limits() {
    local g0=$1 g1=$2
    echo -e "\n${BOLD}Verification:${RESET}"
    local result
    result=$(nvidia-smi --query-gpu=index,enforced.power.limit --format=csv,noheader 2>/dev/null)
    local e0 e1
    e0=$(echo "$result" | awk -F', ' 'NR==1{print int($2)}')
    e1=$(echo "$result" | awk -F', ' 'NR==2{print int($2)}')

    if [[ "$e0" -eq "$g0" ]]; then
        echo -e "  ${GREEN}GPU 0: enforced.power.limit = ${e0}W ✓${RESET}"
    else
        echo -e "  ${RED}GPU 0: enforced.power.limit = ${e0}W (expected ${g0}W) ✗${RESET}"
    fi
    if [[ "$e1" -eq "$g1" ]]; then
        echo -e "  ${GREEN}GPU 1: enforced.power.limit = ${e1}W ✓${RESET}"
    else
        echo -e "  ${RED}GPU 1: enforced.power.limit = ${e1}W (expected ${g1}W) ✗${RESET}"
    fi
}

also_update_toml() {
    local g0=$1 g1=$2
    local toml
    toml="$(dirname "$0")/../gpu_thermal.toml"
    if [[ ! -f "$toml" ]]; then
        return
    fi
    echo -e "\n${BOLD}Also update gpu_thermal.toml?${RESET}"
    echo "  This keeps the Python watchdog stack in sync with the new limits."
    echo -e "  ${YELLOW}[y/N]${RESET} "
    read -r ans
    if [[ "${ans,,}" == "y" ]]; then
        sed -i -E \
            -e "/^\[gpu\.rtx5080\]/,/^\[/{s/^power_eco = [0-9]+/power_eco = ${g0}/}" \
            -e "/^\[gpu\.rtx5080\]/,/^\[/{s/^power_perf = [0-9]+/power_perf = ${g0}/}" \
            -e "/^\[gpu\.rtx3080\]/,/^\[/{s/^power_eco = [0-9]+/power_eco = ${g1}/}" \
            -e "/^\[gpu\.rtx3080\]/,/^\[/{s/^power_perf = [0-9]+/power_perf = ${g1}/}" \
            "$toml"
        echo -e "${GREEN}gpu_thermal.toml updated.${RESET}"
        echo -e "${YELLOW}Restart gpu-eco-mode.service and gpu-watchdog.service to apply:${RESET}"
        echo "  sudo systemctl restart gpu-eco-mode.service gpu-watchdog.service"
    fi
}

# ── Main wizard ───────────────────────────────────────────────────────────────
main() {
    banner
    current_state

    echo -e "\n${BOLD}Select a rollback target:${RESET}"
    local i=1
    for cp in "${CHECKPOINTS[@]}"; do
        IFS='|' read -r label g0 g1 date notes <<< "$cp"
        if [[ -z "$g0" ]]; then
            printf "  %d) %-26s  — %s\n" "$i" "$label" "$notes"
        else
            printf "  %d) %-26s  GPU0=%sW, GPU1=%sW  (%s)\n" "$i" "$label" "$g0" "$g1" "$date"
        fi
        (( i++ ))
    done
    echo -e "  q) Quit (no changes)"

    echo ""
    printf "${YELLOW}Choice [1-%d / q]: ${RESET}" "${#CHECKPOINTS[@]}"
    read -r choice

    if [[ "${choice,,}" == "q" ]]; then
        echo "Aborted — no changes made."
        exit 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#CHECKPOINTS[@]} )); then
        echo -e "${RED}Invalid choice.${RESET}" >&2
        exit 1
    fi

    IFS='|' read -r label g0 g1 date notes <<< "${CHECKPOINTS[$((choice-1))]}"

    # Custom value branch
    if [[ -z "$g0" ]]; then
        echo -e "\n${BOLD}Custom power limits${RESET}"
        printf "  GPU 0 (RTX 5080) — range [%d–%d W]: " "$GPU0_MIN" "$GPU0_MAX"
        read -r g0
        printf "  GPU 1 (RTX 3080) — range [%d–%d W]: " "$GPU1_MIN" "$GPU1_MAX"
        read -r g1
        if ! [[ "$g0" =~ ^[0-9]+$ && "$g1" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}ERROR: values must be integers.${RESET}" >&2
            exit 1
        fi
    fi

    echo -e "\n${BOLD}Rollback plan:${RESET}"
    printf "  Target : %s (%s)\n" "$label" "$date"
    printf "  GPU 0  : %dW\n" "$g0"
    printf "  GPU 1  : %dW\n" "$g1"
    echo -e "\n  ${YELLOW}Confirm? [y/N]${RESET} "
    read -r confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "Aborted — no changes made."
        exit 0
    fi

    apply_limits "$g0" "$g1"
    verify_limits "$g0" "$g1"
    persist_service "$g0" "$g1"
    also_update_toml "$g0" "$g1"

    echo -e "\n${GREEN}${BOLD}Rollback complete.${RESET}"
    current_state
}

main "$@"
