#!/usr/bin/env bash
# 01-install-wsl-tools.sh — install the WSL-side tools:
#   - fastboot (flash the phone from Linux)
#   - usbip client (so usbipd-win can attach the phone into WSL)
#   - pmbootstrap from GIT (the apt version is usually too old for current pmaports)
set -euo pipefail

echo "== apt: fastboot + usbip client deps + git =="
sudo apt-get update
sudo apt-get install -y fastboot linux-tools-virtual hwdata git

echo "== wire up the 'usbip' command (from linux-tools) =="
USBIP_BIN="$(ls /usr/lib/linux-tools/*/usbip 2>/dev/null | tail -n1)"
if [ -n "${USBIP_BIN:-}" ]; then
  sudo update-alternatives --install /usr/local/bin/usbip usbip "$USBIP_BIN" 20
else
  echo "WARNING: usbip binary not found in linux-tools."
fi

echo "== load the USB/IP kernel module =="
sudo modprobe vhci-hcd && echo "vhci-hcd ok" || {
  echo "ERROR: your WSL2 kernel lacks vhci-hcd (USB/IP). Update WSL ('wsl --update') or use a kernel with CONFIG_USBIP_VHCI_HCD."
  exit 1
}

echo "== pmbootstrap from git (latest) =="
if [ ! -d "$HOME/pmbootstrap" ]; then
  git clone --depth=1 https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git "$HOME/pmbootstrap"
fi
sudo ln -sf "$HOME/pmbootstrap/pmbootstrap.py" /usr/local/bin/pmbootstrap
hash -r

echo ""
echo "fastboot : $(fastboot --version 2>&1 | head -1)"
echo "usbip    : $(usbip version 2>&1 | head -1)"
echo "pmbootstrap: $(pmbootstrap --version 2>&1 | head -1)"
echo "Done. Next: put phone in fastboot and run ./bridge-phone.sh"
