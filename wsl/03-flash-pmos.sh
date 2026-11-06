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

Flashed. The phone is booting pmOS (first boot ~1-3 min; the OEM logo may stay frozen —
that's just the splash, pmOS runs headless behind it).

To get in:
  ./bridge-phone.sh          # re-bridges the booted phone's USB-network gadget
  ssh user@172.16.42.1       # password you set during build

If no USB-network interface appears after a few minutes, see docs/TROUBLESHOOTING.md
(archived port: the kernel may not boot; try a stable channel or the 'alpine' kernel).
EOF
