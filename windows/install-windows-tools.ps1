# install-windows-tools.ps1
# Run in an ELEVATED (Admin) PowerShell:
#   powershell -ExecutionPolicy Bypass -File windows\install-windows-tools.ps1
#
# Installs the two Windows-side tools:
#   - Google Platform Tools (fastboot/adb)
#   - usbipd-win (bridges USB devices into WSL2)
#
# NOTE: run this from a real Admin PowerShell window. winget's elevation does NOT
# surface reliably when launched from inside WSL, which is why this is a separate step.

$ErrorActionPreference = 'Stop'

function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Please run this script in an ELEVATED (Administrator) PowerShell."
  }
}
Require-Admin

Write-Host "== Installing Google Platform Tools (fastboot/adb) ==" -ForegroundColor Cyan
winget install --id Google.PlatformTools --source winget `
  --accept-package-agreements --accept-source-agreements

Write-Host "== Installing usbipd-win ==" -ForegroundColor Cyan
winget install --id dorssel.usbipd-win --source winget `
  --accept-package-agreements --accept-source-agreements

Write-Host ""
Write-Host "Done. Open a NEW terminal so PATH updates take effect." -ForegroundColor Green
Write-Host "Next: put the phone on the FASTBOOT screen and run wsl/bridge-phone.sh inside WSL."
