#!/usr/bin/env bash
# 03-flash-pmos.sh — unlock the bootloader and flash the built postmarketOS image.
#
# Prereqs:
#   - ./02-build-pmos.sh completed
#   - phone on the FASTBOOT screen and bridged in (./bridge-phone.sh -> "PHONE READY")
#   - Developer Options -> "OEM unlocking" ENABLED on the phone (else unlock is refused)
#
# ⚠️ THIS WIPES THE PHONE.
set -uo pipefail

EXPORT_DIR="/tmp/postmarketOS-export"

echo "== check phone is in fastboot =="
if ! sudo fastboot devices 2>&1 | grep -q fastboot; then
  echo "Phone not in fastboot. Run ./bridge-phone.sh first (phone on FASTBOOT screen)."; exit 1
fi

echo "== unlock bootloader (if not already) =="
if sudo fastboot getvar unlocked 2>&1 | grep -q 'unlocked: yes'; then
  echo "Already unlocked."
else
  echo ">>> WATCH THE PHONE: a confirm screen appears — Volume to select UNLOCK, Power to confirm."
  echo ">>> The phone will WIPE and reboot. Then put it back in fastboot and re-run bridge-phone.sh + this script."
  sudo fastboot flashing unlock || sudo fastboot oem unlock || true
  echo "If it wiped/rebooted: get back to fastboot, ./bridge-phone.sh, then re-run ./03-flash-pmos.sh"
  # stop here if it just unlocked+rebooted; a second run will proceed to flashing
  sudo fastboot getvar unlocked 2>&1 | grep -q 'unlocked: yes' || exit 0
fi

echo "== export images =="
pmbootstrap export
ls -lL "$EXPORT_DIR"/boot.img "$EXPORT_DIR"/*dumpling*.img

ROOTFS="$(ls "$EXPORT_DIR"/*dumpling*.img | head -1)"
echo "== flash boot =="
sudo fastboot flash boot "$EXPORT_DIR/boot.img"
echo "== flash rootfs -> userdata (big; ~15s+) =="
sudo fastboot flash userdata "$ROOTFS"

echo "== reboot into postmarketOS =="
sudo fastboot reboot

cat <<'EOF'

Flashed. The phone is booting pmOS (first boot ~1-3 min). The OEM logo may stay on screen, or you
may see console text ending at a "dumpling login:" prompt — both are fine. It runs HEADLESS; you do
NOT log in on the phone. You log in over the USB cable from your laptop.

To get in (the phone's USB network is RNDIS, which WSL can't drive but WINDOWS can natively):
  1) In Windows PowerShell:  powershell -ExecutionPolicy Bypass -File windows\setup-usb-network.ps1
  2) From a WINDOWS terminal (NOT WSL):  ssh user@172.16.42.1     # password you set during build

See docs/ACCESS.md for details and docs/TROUBLESHOOTING.md if the phone bootloops or no adapter shows.
EOF
