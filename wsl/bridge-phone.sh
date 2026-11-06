#!/usr/bin/env bash
# bridge-phone.sh — bridge the OnePlus 5T's USB into WSL2 via usbipd-win so native Linux
# `fastboot` can see it. This is for FASTBOOT mode (18d1:d00d) — building and flashing.
#
# NOTE: after pmOS boots, its USB network is RNDIS, which the WSL2 kernel CANNOT drive (no
# rndis_host module). Do NOT use this to reach the booted phone — use Windows instead:
# windows/setup-usb-network.ps1 + `ssh user@172.16.42.1` from a Windows terminal. See docs/ACCESS.md.
#
# Idempotent. Re-run any time the fastboot connection resets (reboot, replug).
set -uo pipefail

USBIPD='C:\Program Files\usbipd-win\usbipd.exe'
# USB IDs we consider "the phone": fastboot (18d1:d00d) + common pmOS/Qualcomm gadget IDs.
# Anything that is NOT a known laptop device is treated as the phone.
# Edit KNOWN_NOT_PHONE for your machine (run `usbipd list` to see your built-ins).
KNOWN_NOT_PHONE='BUSID|Integrated Camera|Wireless Bluetooth|USB Input Device'

ps()  { powershell.exe -NoProfile -Command "$1" 2>&1 | tr -d '\r'; }
say() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

say "1/4 load usbip kernel module"
sudo modprobe vhci-hcd && echo "vhci-hcd ok" || { echo "FAILED to load vhci-hcd (is this WSL2 with USB/IP support?)"; exit 1; }

say "2/4 find the phone in usbipd"
LIST="$(ps "& '$USBIPD' list")"
LINE="$(printf '%s\n' "$LIST" | grep -iE '^[0-9]+-[0-9]' | grep -ivE "$KNOWN_NOT_PHONE" | head -1)"
if [ -z "$LINE" ]; then
  echo "No phone-like USB device found. Is it plugged in and powered (fastboot screen, or booted)?"
  echo "Current usbipd list:"; printf '%s\n' "$LIST"
  exit 1
fi
BUSID="$(printf '%s\n' "$LINE" | awk '{print $1}')"
echo "found: $LINE"
echo "busid = $BUSID"

say "3/4 ensure shared + attach to WSL"
if printf '%s\n' "$LINE" | grep -qi 'Not shared'; then
  echo ">>> binding (needs admin) — CLICK YES on the Windows UAC popup..."
  ps "Start-Process '$USBIPD' -ArgumentList 'bind','--busid','$BUSID' -Verb RunAs -Wait" >/dev/null
fi
ps "& '$USBIPD' attach --wsl --busid $BUSID" | grep -viE '^\s*$|info:' || true
sleep 3

say "4/4 verify"
if sudo fastboot devices 2>&1 | grep -q fastboot; then
  echo "FASTBOOT mode:"; sudo fastboot devices
  echo -n "product: "; sudo fastboot getvar product 2>&1 | awk -F': ' '/product:/{print $2; exit}'
  echo -e "\n\033[1;32mPHONE READY (fastboot).\033[0m"
else
  echo "Device attached but NOT in fastboot."
  echo "If pmOS has booted, its network is RNDIS and WSL can't drive it — switch to Windows:"
  echo "  1) usbipd detach/unbind busid $BUSID (so Windows owns it), then"
  echo "  2) windows\\setup-usb-network.ps1  +  ssh user@172.16.42.1  (from a Windows terminal)."
  echo "See docs/ACCESS.md. If you expected fastboot, make sure the phone is on the fastboot screen."
fi
