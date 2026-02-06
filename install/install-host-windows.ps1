# install-host-windows.ps1 — helper notes for Windows host setup.
# Run this in PowerShell (no admin required for most steps).

Write-Host "=== devmux Windows Host Setup Notes ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Ensure OpenSSH Server is running:" -ForegroundColor Yellow
Write-Host "   - Settings > Apps > Optional Features > OpenSSH Server"
Write-Host "   - Or: Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'"
Write-Host "   - Start service: Start-Service sshd"
Write-Host "   - Auto-start:    Set-Service -Name sshd -StartupType Automatic"
Write-Host ""
Write-Host "2. Ensure WSL is installed with Ubuntu:" -ForegroundColor Yellow
Write-Host "   - wsl --install -d Ubuntu"
Write-Host ""
Write-Host "3. Install devmux-remote INSIDE WSL:" -ForegroundColor Yellow
Write-Host "   - Open WSL: wsl -d Ubuntu"
Write-Host "   - Clone or copy the devmux repo"
Write-Host "   - Run: bash install/install-host-wsl.sh"
Write-Host ""
Write-Host "4. Ensure Tailscale is installed and logged in." -ForegroundColor Yellow
Write-Host "   - https://tailscale.com/download"
Write-Host ""
Write-Host "5. Test from a client:" -ForegroundColor Yellow
Write-Host "   ssh <this-pc> `"wsl -d Ubuntu --exec bash -lc 'devmux-remote --list-projects'`""
Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
