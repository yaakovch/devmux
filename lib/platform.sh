#!/usr/bin/env bash
# lib/platform.sh — platform detection helpers.
# Source this file; do not execute directly.

# Detect the current platform.
# Outputs one of: wsl | linux | termux | macos
detect_platform() {
    if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
        echo "termux"
    elif [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "linux"
    fi
}

# Detect the hostname, normalized to lowercase with hyphens.
detect_hostname() {
    hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "unknown"
}
