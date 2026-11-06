#!/usr/bin/env bash
# bridge-phone.sh — bridge the OnePlus 5T's USB into WSL2 via usbipd-win, so native
# Linux `fastboot` (and, once booted, the USB-network gadget) can see it.
#
# Run it with the phone connected. Works for the phone in FASTBOOT mode (18d1:d00d)
# and, after pmOS boots, for its USB-network gadget (auto-detects whatever shows up).
#
# Idempotent. Re-run any time the connection resets (reboot, replug).
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
  echo "Not in fastboot. If pmOS is booted, a USB network interface should appear:"
  ip -brief addr show 2>/dev/null | grep -iE 'usb|enx|172\.16\.42' || echo "  (no usb net iface yet — give it ~30s and re-run, or it may still be booting)"
  echo "If booted: ssh user@172.16.42.1"
fi
