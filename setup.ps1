#Requires -RunAsAdministrator
# setup.ps1 — bootstrap devmux on a Windows host.
# Run this in an ADMIN PowerShell. Handles OpenSSH, authorized_keys, SSH config, WSL.
param(
    [string]$WslDistro = "Ubuntu",
    [switch]$SkipWsl,
    [switch]$SkipShim
)

$ErrorActionPreference = "Stop"
$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "=== devmux Windows host setup ===" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Check admin privileges ───────────────────────────────
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell → 'Run as administrator', then re-run." -ForegroundColor Yellow
    exit 1
}
Write-Host "  Running as Administrator" -ForegroundColor Green

# ── Step 2: Ensure OpenSSH Server ────────────────────────────────
Write-Host ""
Write-Host "-- OpenSSH Server --" -ForegroundColor Yellow

$sshdService = Get-Service -Name sshd -ErrorAction SilentlyContinue
if (-not $sshdService) {
    Write-Host "  Installing OpenSSH Server..."
    $cap = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"
    if ($cap) {
        Add-WindowsCapability -Online -Name $cap.Name
    } else {
        Write-Host "  ERROR: OpenSSH Server capability not found." -ForegroundColor Red
        Write-Host "  Install manually: Settings > Apps > Optional Features > OpenSSH Server" -ForegroundColor Yellow
        exit 1
    }
}

Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType Automatic
Write-Host "  sshd: running (auto-start enabled)" -ForegroundColor Green

# ── Step 3: Collect public keys ──────────────────────────────────
Write-Host ""
Write-Host "-- SSH Public Keys --" -ForegroundColor Yellow

$keys = @()

# Try reading from WSL
if (-not $SkipWsl) {
    $wslKeyPath = "\\wsl$\$WslDistro\home\$env:USERNAME\.ssh\id_ed25519.pub"
    # Also try common WSL usernames
    $wslPaths = @(
        "\\wsl$\$WslDistro\home\$env:USERNAME\.ssh\id_ed25519.pub"
    )
    # Check wsl users
    try {
        $wslUsers = wsl -d $WslDistro -- bash -c "ls /home/ 2>/dev/null" 2>$null
        if ($wslUsers) {
            foreach ($u in ($wslUsers -split "`n" | Where-Object { $_.Trim() -ne "" })) {
                $wslPaths += "\\wsl$\$WslDistro\home\$u\.ssh\id_ed25519.pub"
            }
        }
    } catch {}

    foreach ($p in ($wslPaths | Select-Object -Unique)) {
        if (Test-Path $p) {
            $k = (Get-Content $p -Raw).Trim()
            if ($k -and ($keys -notcontains $k)) {
                $keys += $k
                Write-Host "  Found key from WSL: $p" -ForegroundColor Green
            }
        }
    }
}

# Try reading from a file argument or prompt
if ($keys.Count -eq 0) {
    Write-Host "  No keys found automatically." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "    1. Paste a public key now"
    Write-Host "    2. Skip (add keys later)"
    Write-Host ""
    $choice = Read-Host "  Choice [1/2]"
    if ($choice -eq "1") {
        $pastedKey = Read-Host "  Paste your public key"
        $pastedKey = $pastedKey.Trim()
        if ($pastedKey -match "^ssh-") {
            $keys += $pastedKey
        } else {
            Write-Host "  WARNING: That doesn't look like an SSH public key. Skipping." -ForegroundColor Yellow
        }
    }
}

# ── Step 4: Write administrators_authorized_keys ─────────────────
if ($keys.Count -gt 0) {
    Write-Host ""
    Write-Host "-- Authorized Keys --" -ForegroundColor Yellow

    $keyFile = "C:\ProgramData\ssh\administrators_authorized_keys"
    $sshDir = "C:\ProgramData\ssh"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    # Read existing keys
    $existing = @()
    if (Test-Path $keyFile) {
        $existing = @(Get-Content $keyFile | Where-Object { $_.Trim() -ne "" })
    }

    # Merge and deduplicate
    $allKeys = @($existing)
    $added = 0
    foreach ($k in $keys) {
        if ($allKeys -notcontains $k) {
            $allKeys += $k
            $added++
        }
    }

    # Write with UTF-8 no BOM
    $content = ($allKeys -join "`n") + "`n"
    [System.IO.File]::WriteAllText($keyFile, $content, (New-Object System.Text.UTF8Encoding $false))

    Write-Host "  Written to: $keyFile ($added new key(s))" -ForegroundColor Green

    # ── Step 5: Fix permissions ──────────────────────────────────
    icacls $keyFile /inheritance:r /grant "SYSTEM:(R)" /grant "BUILTIN\Administrators:(R)" | Out-Null
    Write-Host "  Permissions fixed (SYSTEM + Administrators only)" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  No keys to install. You can add them later by re-running this script." -ForegroundColor Yellow
}

# ── Step 6: Generate SSH config ──────────────────────────────────
Write-Host ""
Write-Host "-- SSH Config --" -ForegroundColor Yellow

$winSshConfig = "$env:USERPROFILE\.ssh\config"
$winSshDir = "$env:USERPROFILE\.ssh"

if (-not (Test-Path $winSshDir)) {
    New-Item -ItemType Directory -Path $winSshDir -Force | Out-Null
}

# Parse machines.conf for SSH config generation
$machinesConf = Get-Content "$RepoDir\machines.conf" -ErrorAction SilentlyContinue
$beginMarker = "# BEGIN devmux-managed"
$endMarker = "# END devmux-managed"

if ($machinesConf) {
    # Extract machine entries from machines.conf
    $configBlock = @($beginMarker)

    # Simple parser: find TAILSCALE_IP and WIN_USER entries
    $machinePattern = 'MACHINE_(\w+)_TAILSCALE_IP="([^"]+)"'
    $userPattern = 'MACHINE_(\w+)_WIN_USER="([^"]+)"'

    $ips = @{}
    $users = @{}

    foreach ($line in $machinesConf) {
        if ($line -match $machinePattern) {
            $name = $Matches[1] -replace '_', '-'
            $ips[$name] = $Matches[2]
        }
        if ($line -match $userPattern) {
            $name = $Matches[1] -replace '_', '-'
            $users[$name] = $Matches[2]
        }
    }

    foreach ($name in $ips.Keys) {
        $configBlock += ""
        $configBlock += "Host $name"
        $configBlock += "    HostName $($ips[$name])"
        if ($users.ContainsKey($name)) {
            $configBlock += "    User $($users[$name])"
        }
    }

    $configBlock += ""
    $configBlock += $endMarker

    # Read existing config, strip old managed block, append new
    $existingConfig = @()
    if (Test-Path $winSshConfig) {
        $inBlock = $false
        foreach ($line in (Get-Content $winSshConfig)) {
            if ($line -eq $beginMarker) { $inBlock = $true; continue }
            if ($line -eq $endMarker) { $inBlock = $false; continue }
            if (-not $inBlock) { $existingConfig += $line }
        }
    }

    $finalConfig = @($existingConfig) + @("") + $configBlock
    $finalContent = ($finalConfig -join "`n") + "`n"
    [System.IO.File]::WriteAllText($winSshConfig, $finalContent, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "  Updated: $winSshConfig (devmux-managed block)" -ForegroundColor Green
} else {
    Write-Host "  machines.conf not found — skipping SSH config generation." -ForegroundColor Yellow
}

# ── Step 7: Offer to run setup.sh in WSL ─────────────────────────
if (-not $SkipWsl) {
    Write-Host ""
    Write-Host "-- WSL Setup --" -ForegroundColor Yellow

    $wslInstalled = $false
    try {
        $wslList = wsl --list --quiet 2>$null
        if ($wslList -match $WslDistro) {
            $wslInstalled = $true
        }
    } catch {}

    if ($wslInstalled) {
        Write-Host "  WSL distro '$WslDistro' is available." -ForegroundColor Green

        $runWsl = Read-Host "  Run setup.sh inside WSL now? [y/N]"
        if ($runWsl -match "^[Yy]$") {
            # Convert repo path to WSL path
            $driveLetter = $RepoDir.Substring(0, 1).ToLower()
            $wslPath = "/mnt/$driveLetter" + ($RepoDir.Substring(2) -replace '\\', '/')
            Write-Host "  Running: wsl -d $WslDistro -- bash '$wslPath/setup.sh'" -ForegroundColor Cyan
            wsl -d $WslDistro -- bash "$wslPath/setup.sh"
        }
    } else {
        Write-Host "  WSL distro '$WslDistro' not found." -ForegroundColor Yellow
        Write-Host "  Install it with: wsl --install -d $WslDistro" -ForegroundColor Yellow
    }
}

# ── Step 8: Install Windows devmux shim (optional) ───────────────
if (-not $SkipShim) {
    Write-Host ""
    Write-Host "-- Windows devmux command --" -ForegroundColor Yellow

    $shimDir = Join-Path $env:USERPROFILE ".local\bin"
    $shimPath = Join-Path $shimDir "devmux.cmd"

    if (-not (Test-Path $shimDir)) {
        New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
    }

    # A simple shim that launches devmux inside WSL.
    # Supports forwarding args: `devmux --host work-m ...`
    # Use a *single-quoted* here-string to avoid PowerShell expanding `$@`.
    $shimContent = (@'
@echo off
setlocal
set "DISTRO=%DEVMUX_WSL_DISTRO%"
if "%DISTRO%"=="" set "DISTRO={0}"
wsl -d %DISTRO% --exec bash -lc "devmux \"$@\"" devmux %*
endlocal
'@ -f $WslDistro)

    [System.IO.File]::WriteAllText($shimPath, $shimContent, [System.Text.Encoding]::ASCII)
    Write-Host "  Installed: $shimPath" -ForegroundColor Green

    # Ensure shim dir is in the *user* PATH so `devmux` works from any folder.
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $userPath) { $userPath = "" }
    $parts = @($userPath -split ";" | Where-Object { $_.Trim() -ne "" })
    if (-not ($parts -contains $shimDir)) {
        $newPath = @($parts + $shimDir) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "  Added to user PATH: $shimDir" -ForegroundColor Green
        Write-Host "  Open a new terminal to pick up PATH changes." -ForegroundColor Yellow
    } else {
        Write-Host "  Already on user PATH: $shimDir" -ForegroundColor Green
    }

    Write-Host "  Usage: devmux" -ForegroundColor Cyan
    Write-Host "  Override distro: set DEVMUX_WSL_DISTRO=Ubuntu-22.04" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=== Windows setup complete ===" -ForegroundColor Green
Write-Host "  Test from a client: ssh $(hostname) `"wsl -d $WslDistro --exec bash -lc 'devmux-remote --list-projects'`"" -ForegroundColor Cyan
Write-Host ""
