#!/usr/bin/env bash
# lib/tailscale.sh — Tailscale detection and helpers.
# Source this file; do not execute directly.

# Find the best tailscale CLI binary for this platform.
# On WSL: prefer tailscale.exe (Windows interop — no WSL install needed).
# On native Linux/Termux: use tailscale.
# Prints the binary name/path, or empty string if not found.
find_tailscale_cli() {
    # WSL: prefer Windows Tailscale via interop
    if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
        if command -v tailscale.exe &>/dev/null; then
            echo "tailscale.exe"
            return 0
        fi
    fi

    # Native tailscale
    if command -v tailscale &>/dev/null; then
        echo "tailscale"
        return 0
    fi

    return 1
}

# Check if tailscale CLI is available and connected.
tailscale_available() {
    command -v tailscale &>/dev/null && tailscale status &>/dev/null
}

# Get this machine's Tailscale IPv4 address.
tailscale_my_ip() {
    tailscale ip -4 2>/dev/null
}

# Try to identify which machine we are based on Tailscale IP.
# Usage: tailscale_identify_self  (prints machine key from machines.conf or "")
# Requires machines.conf to be sourced first.
tailscale_identify_self() {
    local my_ip
    my_ip=$(tailscale_my_ip) || return 1
    [[ -z "$my_ip" ]] && return 1

    local machine var_name machine_ip
    for machine in "${MACHINES[@]}"; do
        var_name="MACHINE_${machine//-/_}_TAILSCALE_IP"
        machine_ip="${!var_name:-}"
        if [[ "$machine_ip" == "$my_ip" ]]; then
            echo "$machine"
            return 0
        fi
    done
    return 1
}

# Check if tailscale ssh works to a given target.
# Usage: tailscale_ssh_reachable "100.83.144.22" "yaako"
tailscale_ssh_reachable() {
    local ip="$1" user="${2:-}"
    local target="${user:+$user@}$ip"
    tailscale ssh -o ConnectTimeout=3 "$target" true &>/dev/null 2>&1
}
