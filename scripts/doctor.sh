#!/usr/bin/env bash
# scripts/doctor.sh — quick connectivity checks for devmux.
#
# Usage:
#   bash scripts/doctor.sh
#
# This does not modify anything. It checks:
# - devmux.conf exists
# - each host in config is reachable via SSH without prompting for a password
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/devmux"
CONFIG_FILE="$CONFIG_DIR/devmux.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "FAIL: Config not found: $CONFIG_FILE" >&2
    echo "Run: bash setup.sh --regen-config" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

if [[ -f "$REPO_DIR/machines.conf" ]]; then
    # shellcheck source=/dev/null
    source "$REPO_DIR/machines.conf"
fi

ok=0
fail=0

echo "devmux doctor"
echo "  config: $CONFIG_FILE"
echo ""

hosts=("${HOSTS[@]-}")
if [[ ${#hosts[@]} -eq 0 ]]; then
    echo "FAIL: HOSTS is empty in devmux.conf" >&2
    exit 1
fi

for host in "${hosts[@]}"; do
    ssh_target_var="HOST_${host//-/_}_SSH"
    wsl_prefix_var="HOST_${host//-/_}_WSL_PREFIX"

    ssh_target="${!ssh_target_var:-}"
    wsl_prefix="${!wsl_prefix_var:-}"

    if [[ -z "$ssh_target" ]]; then
        echo "FAIL: $host: $ssh_target_var not set"
        fail=$((fail + 1))
        continue
    fi

    if [[ "$ssh_target" == "local" || "$ssh_target" == "localhost" || "$ssh_target" == "127.0.0.1" || "$ssh_target" == "::1" ]]; then
        echo "OK:   $host (local)"
        ok=$((ok + 1))
        continue
    fi

    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$ssh_target" "echo ok" >/dev/null 2>&1; then
        echo "OK:   $host ($ssh_target) ssh"
        ok=$((ok + 1))
    else
        echo "FAIL: $host ($ssh_target) ssh"
        # If this is a Windows host, the fix is usually authorized_keys.
        if [[ -n "${MACHINES[*]:-}" ]]; then
            mp="MACHINE_${host//-/_}"
            os_var="${mp}_OS"
            os="${!os_var:-}"
            if [[ "$os" == "windows-wsl" ]]; then
                echo "      hint: On this client: bash \"$REPO_DIR/scripts/show-key.sh\""
                echo "            On $host (Windows, Admin PowerShell): run setup.ps1 and add this client key with -AddKey"
            fi
        fi
        fail=$((fail + 1))
    fi

    if [[ -n "$wsl_prefix" ]]; then
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$ssh_target" "$wsl_prefix \"echo wsl-ok\"" >/dev/null 2>&1; then
            echo "      OK:   $host WSL prefix"
        else
            echo "      WARN: $host WSL prefix failed"
        fi
    fi
done

echo ""
echo "Summary: OK=$ok FAIL=$fail"

if [[ $fail -gt 0 ]]; then
    exit 2
fi
