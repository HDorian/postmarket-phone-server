# setup-usb-network.ps1
# Run in Windows PowerShell AFTER the phone has booted postmarketOS:
#   powershell -ExecutionPolicy Bypass -File windows\setup-usb-network.ps1
#
# postmarketOS exposes its network over the USB cable as an RNDIS gadget. The WSL2 kernel can't
# drive RNDIS, but Windows can natively — so you reach the phone from Windows. This script:
#   1) checks Windows has the phone's RNDIS network adapter (and guides the one-time driver pick),
#   2) checks it has an IP on the phone's 172.16.42.0/24 network,
#   3) verifies the phone (172.16.42.1) answers ping + SSH, and prints the ssh command.
#
# Phone = 172.16.42.1, Windows host gets 172.16.42.2 by DHCP from the phone.

$ErrorActionPreference = "SilentlyContinue"
$PHONE = "172.16.42.1"
function Info($m){ Write-Host $m -ForegroundColor Cyan }
function Ok($m){ Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }

Info "== 1. Looking for the phone's RNDIS device =="
$pnp = Get-PnpDevice -PresentOnly | Where-Object {
  $_.InstanceId -match 'VID_18D1&PID_D001' -or $_.FriendlyName -match 'RNDIS|Remote NDIS|OnePlus'
}
if (-not $pnp) {
  Warn "No RNDIS device found. Is the phone booted and the USB cable connected to THIS PC?"
  Warn "If you earlier bridged it into WSL with usbipd, release it back to Windows first:"
  Warn "    usbipd detach --busid <id>   &&   usbipd unbind --busid <id>   (unbind needs Admin)"
  exit 1
}
$pnp | Format-Table -Auto Status, Class, FriendlyName | Out-String | Write-Host

$adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'Remote NDIS|RNDIS' }

if (-not $adapter) {
  Warn "Windows sees the phone but hasn't loaded a network driver for it (Linux RNDIS doesn't"
  Warn "auto-install). Do this ONE-TIME driver assignment, then re-run this script:"
  Write-Host ""
  Write-Host "  1. Win+X -> Device Manager" -ForegroundColor White
  Write-Host "  2. Find 'RNDIS' with a yellow warning (under Other devices, or Network adapters)" -ForegroundColor White
  Write-Host "  3. Right-click -> Update driver" -ForegroundColor White
  Write-Host "  4. 'Browse my computer for drivers'" -ForegroundColor White
  Write-Host "  5. 'Let me pick from a list of available drivers on my computer'" -ForegroundColor White
  Write-Host "  6. If asked for a type: Network adapters -> Next" -ForegroundColor White
  Write-Host "  7. Manufacturer: Microsoft  ->  'Remote NDIS Compatible Device'" -ForegroundColor White
  Write-Host "     (fallbacks: 'USB RNDIS Adapter' / 'Remote NDIS based Internet Sharing Device')" -ForegroundColor White
  Write-Host "  8. Next -> accept any warning -> Close" -ForegroundColor White
  exit 1
}
Ok ("Network adapter present: '{0}' ({1}) - {2}" -f $adapter.Name, $adapter.InterfaceDescription, $adapter.Status)

Info "== 2. Checking this PC's IP on the phone network =="
$ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $adapter.ifIndex |
      Where-Object { $_.IPAddress -like '172.16.42.*' }
if ($ip) {
  Ok ("Have {0} (via {1}) on the phone's network." -f $ip.IPAddress, $ip.PrefixOrigin)
} else {
  Warn "No 172.16.42.x address yet (DHCP from the phone may still be coming up)."
  Warn "Wait ~15 s and re-run. If it never appears, set a static IP in an ADMIN PowerShell:"
  Warn ("    New-NetIPAddress -InterfaceIndex {0} -IPAddress 172.16.42.2 -PrefixLength 24" -f $adapter.ifIndex)
}

Info "== 3. Can we reach the phone? =="
$ping = Test-Connection -ComputerName $PHONE -Count 2 -Quiet
$ssh  = (Test-NetConnection $PHONE -Port 22 -WarningAction SilentlyContinue).TcpTestSucceeded
if ($ping) { Ok "ping $PHONE : OK" } else { Warn "ping $PHONE : no reply (yet)" }
if ($ssh)  { Ok "ssh port 22 : OPEN" } else { Warn "ssh port 22 : closed/unreachable (yet)" }

Write-Host ""
if ($ping -and $ssh) {
  Ok "Ready. Log in from this Windows terminal:"
  Write-Host "    ssh user@$PHONE" -ForegroundColor White
  Write-Host "    (password set during the build; default 'changeme123' - change it!)" -ForegroundColor White
} else {
  Warn "Not reachable yet. Give the phone a minute after boot and re-run this script."
}
