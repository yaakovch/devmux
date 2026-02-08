#!/usr/bin/env bash
# lib/ssh.sh — SSH key management and config generation.
# Source this file; do not execute directly.
# Depends on: lib/common.sh (die, info, confirm)

SSH_KEY_TYPE="ed25519"
SSH_MANAGED_MARKER="devmux-managed"
SSH_MANAGED_BEGIN="# BEGIN ${SSH_MANAGED_MARKER}"
SSH_MANAGED_END="# END ${SSH_MANAGED_MARKER}"

# ── Key generation ────────────────────────────────────────────────

# Ensure an SSH key exists, generate if missing.
# Usage: ensure_ssh_key [key_path]
ensure_ssh_key() {
    local key_path="${1:-$HOME/.ssh/id_${SSH_KEY_TYPE}}"
    if [[ -f "$key_path" ]]; then
        info "  SSH key exists: $key_path"
        return 0
    fi
    info "  Generating SSH key: $key_path"
    mkdir -p "$(dirname "$key_path")"
    ssh-keygen -t "$SSH_KEY_TYPE" -f "$key_path" -N "" -C "devmux@$(hostname -s 2>/dev/null || echo unknown)"
    info "  Created: $key_path"
}

# ── Key distribution — Linux/WSL target ──────────────────────────

# Deploy a public key to a Linux/WSL host via SSH.
# Usage: deploy_key_linux "user@host" [pub_key_path]
deploy_key_linux() {
    local target="$1"
    local pub_key="${2:-$HOME/.ssh/id_${SSH_KEY_TYPE}.pub}"

    if [[ ! -f "$pub_key" ]]; then
        die "Public key not found: $pub_key"
    fi

    info "  Deploying key to $target..."
    ssh-copy-id -i "$pub_key" "$target" 2>/dev/null && return 0

    # Fallback: manual append
    local key_content
    key_content=$(<"$pub_key")
    # shellcheck disable=SC2029
    ssh "$target" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qF '${key_content}' ~/.ssh/authorized_keys 2>/dev/null || echo '${key_content}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
}

# ── Key distribution — Windows target ────────────────────────────

# Print PowerShell commands to deploy a key on a Windows host.
# This handles the admin authorized_keys encoding/permissions pain.
# Usage: deploy_key_windows_commands "pub_key_content" "win_user"
deploy_key_windows_commands() {
    local pub_key_content="$1"
    local win_user="${2:-yaako}"

    cat <<PWSH

# ── Run these commands in an ADMIN PowerShell on the Windows host ──

# Alternative (recommended): if the devmux repo is on this Windows host, run:
#   .\\setup.ps1 -AddKey "<your-public-key>"
# This normalizes whitespace/newlines and fixes permissions automatically.

# 1. Ensure OpenSSH Server is running
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# 2. Write key to administrators_authorized_keys (UTF-8, no BOM)
\$keyFile = "C:\\ProgramData\\ssh\\administrators_authorized_keys"
\$keyRaw = @'
${pub_key_content}
'@
\$key = (\$keyRaw -replace "\\s+", " ").Trim()

# Read existing keys, deduplicate, append new
\$existing = if (Test-Path \$keyFile) { Get-Content \$keyFile } else { @() }
if (\$existing -notcontains \$key) {
    \$all = @(\$existing) + @(\$key) | Where-Object { \$_.Trim() -ne "" }
    [System.IO.File]::WriteAllText(\$keyFile, (\$all -join "\`n") + "\`n", (New-Object System.Text.UTF8Encoding \$false))
    Write-Host "Key added to \$keyFile"
} else {
    Write-Host "Key already present in \$keyFile"
}

# 3. Fix permissions (SYSTEM and Administrators only)
icacls \$keyFile /inheritance:r /grant "SYSTEM:(R)" /grant "BUILTIN\\Administrators:(R)"

PWSH
}

# Deploy key to Windows host via SSH (if SSH already works).
# Usage: deploy_key_windows_ssh "ssh_target" [pub_key_path]
deploy_key_windows_ssh() {
    local target="$1"
    local pub_key="${2:-$HOME/.ssh/id_${SSH_KEY_TYPE}.pub}"

    if [[ ! -f "$pub_key" ]]; then
        die "Public key not found: $pub_key"
    fi

    local key_content
    key_content=$(<"$pub_key")

    info "  Deploying key to Windows host $target..."
    # Use PowerShell over SSH with stdin to avoid quoting issues
    local pwsh_script
    pwsh_script=$(cat <<'PWSH'
$ErrorActionPreference = 'Stop'
$KeyFile = "C:\ProgramData\ssh\administrators_authorized_keys"
$Key = @'
__DEV_MUX_PUBKEY__
'@

$existing = if (Test-Path $KeyFile) { Get-Content $KeyFile } else { @() }
if ($existing -notcontains $Key) {
    $all = @($existing) + @($Key) | Where-Object { $_.Trim() -ne "" }
    [System.IO.File]::WriteAllText($KeyFile, ($all -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
    Write-Host "Key added to $KeyFile"
} else {
    Write-Host "Key already present in $KeyFile"
}

icacls $KeyFile /inheritance:r /grant "SYSTEM:(R)" /grant "BUILTIN\Administrators:(R)" | Out-Null
PWSH
)
    pwsh_script="${pwsh_script/__DEV_MUX_PUBKEY__/$key_content}"
    # shellcheck disable=SC2029
    ssh "$target" "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File -" <<< "$pwsh_script"
}

# ── SSH config generation ────────────────────────────────────────

# Generate SSH config entries from machines.conf.
# Usage: generate_ssh_config  (prints to stdout)
# Requires machines.conf to be sourced first.
generate_ssh_config() {
    local machine var_prefix ts_ip win_user wsl_user os_type
    local ts_ip_var win_user_var os_type_var wsl_user_var

    for machine in "${MACHINES[@]}"; do
        var_prefix="MACHINE_${machine//-/_}"
        ts_ip_var="${var_prefix}_TAILSCALE_IP"
        ts_ip="${!ts_ip_var:-}"
        win_user_var="${var_prefix}_WIN_USER"
        win_user="${!win_user_var:-}"
        os_type_var="${var_prefix}_OS"
        os_type="${!os_type_var:-linux}"

        [[ -z "$ts_ip" ]] && continue

        # Windows hosts: SSH lands on Windows, user is the Windows user
        local ssh_user="$win_user"
        if [[ "$os_type" == "linux" ]] || [[ "$os_type" == "termux" ]]; then
            wsl_user_var="${var_prefix}_WSL_USER"
            wsl_user="${!wsl_user_var:-}"
            ssh_user="$wsl_user"
        fi

        echo "Host ${machine}"
        echo "    HostName ${ts_ip}"
        [[ -n "$ssh_user" ]] && echo "    User ${ssh_user}"
        echo ""
    done
}

# Write SSH config with managed block markers.
# Preserves user entries outside the managed block.
# Usage: write_ssh_config "config_content" [config_path]
write_ssh_config() {
    local content="$1"
    local config_path="${2:-$HOME/.ssh/config}"

    mkdir -p "$(dirname "$config_path")"

    if [[ ! -f "$config_path" ]]; then
        # No existing config — write fresh
        cat > "$config_path" <<EOF
${SSH_MANAGED_BEGIN}
${content}
${SSH_MANAGED_END}
EOF
        chmod 600 "$config_path"
        return
    fi

    # Remove existing managed block and insert new one
    local tmpfile
    tmpfile=$(mktemp)
    local in_block=false
    local found_block=false

    while IFS= read -r line; do
        if [[ "$line" == "${SSH_MANAGED_BEGIN}" ]]; then
            in_block=true
            found_block=true
            continue
        fi
        if [[ "$line" == "${SSH_MANAGED_END}" ]]; then
            in_block=false
            continue
        fi
        if ! $in_block; then
            echo "$line"
        fi
    done < "$config_path" > "$tmpfile"

    # Append managed block at the end
    {
        # Add newline separator if file has content
        if [[ -s "$tmpfile" ]]; then
            # Ensure trailing newline
            [[ "$(tail -c 1 "$tmpfile")" != "" ]] && echo ""
        fi
        echo "${SSH_MANAGED_BEGIN}"
        echo "${content}"
        echo "${SSH_MANAGED_END}"
    } >> "$tmpfile"

    mv "$tmpfile" "$config_path"
    chmod 600 "$config_path"
}
