#!/usr/bin/env bash
# 02-build-pmos.sh — configure postmarketOS for the OnePlus 5T and build a headless image.
#
# Working combo (proven): release channel v26.06 + mainline kernel + OpenRC + ui=none.
#   - The 5T port is ARCHIVED on edge (no prebuilt binaries, and edge didn't boot here), but on the
#     stable v26.06 release it is still a live port WITH prebuilt binaries, so there is NO 40-minute
#     kernel compile — this step is mostly package downloads.
#   - OpenRC (not systemd): lighter, and it's what this port was tested with. systemd-edge would not
#     boot on this device.
#
# Run AFTER ./01-install-wsl-tools.sh. The phone does NOT need to be connected for this step.
set -uo pipefail

CHANNEL="v26.06"
DEVICE="oneplus-dumpling"
KERNEL="mainline"                         # msm8998 qcom kernel; 'alpine' won't drive the hardware
UI="none"
PASSWORD="${PMOS_PASSWORD:-changeme123}"  # override: PMOS_PASSWORD=... ./02-build-pmos.sh

say() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# --- WSL network quirk -------------------------------------------------------------------------
# This machine has no IPv6 default route; pmbootstrap's interactive "best mirror" probe then dies
# (errno 101/99). Disabling IPv6 for the session makes apk/downloads use IPv4 cleanly. Harmless and
# resets on WSL restart. (The init below still errors at the mirror prompt — that is EXPECTED and
# does not matter: `install` uses the default mirror, not that prompt.)
say "disable IPv6 for this WSL session (mirror/download fix)"
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 \
               net.ipv6.conf.default.disable_ipv6=1 \
               net.ipv6.conf.eth0.disable_ipv6=1 >/dev/null 2>&1 || true

# --- pmbootstrap config ------------------------------------------------------------------------
# In pmbootstrap v3 there is NO `channel`/`systemd` config key: the channel is the checked-out
# pmaports branch (switched inside `pmbootstrap init`), and systemd-vs-openrc is `service_manager`.
say "set pmbootstrap config (device / kernel / OpenRC / headless / openssh)"
pmbootstrap config device "$DEVICE"
pmbootstrap config kernel "$KERNEL"
pmbootstrap config ui "$UI"
pmbootstrap config service_manager openrc
pmbootstrap config extra_packages openssh
pmbootstrap config auto_zap_misconfigured_chroots yes   # auto-rebuild chroots if the channel changed

# --- switch to the v26.06 channel via init ----------------------------------------------------
# `ask()` prompts always read stdin (empty = keep current default); `-y` auto-confirms yes/no
# prompts without consuming a line. The channel is the 3rd stdin prompt (after work-path and
# pmaports-path), so we feed: <enter> <enter> v26.06 <enter...>. The init clones pmaports on first
# run, switches the branch, then crashes at the "Select a mirror" probe — that last error is
# expected and harmless.
say "switch channel to $CHANNEL (init; the mirror-step error at the end is expected)"
{ printf '\n\n%s\n' "$CHANNEL"; for _ in $(seq 1 60); do echo; done; } \
  | pmbootstrap -y init --shallow-initial-clone >/tmp/pm-init.log 2>&1 || true

# --- verify the channel actually switched ------------------------------------------------------
PMA="$(pmbootstrap config aports 2>/dev/null | tail -1)"
BRANCH="$(git -C "${PMA:-$HOME/.local/var/pmbootstrap/cache_git/pmaports}" rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ "$BRANCH" != "$CHANNEL" ]; then
  echo "!! pmaports is on '$BRANCH', expected '$CHANNEL'."
  echo "   Run 'pmbootstrap init' manually and choose '$CHANNEL' at the channel prompt, then re-run."
  echo "   (init log: /tmp/pm-init.log)"
  exit 1
fi
say "config summary"
pmbootstrap status

# --- build the rootfs image --------------------------------------------------------------------
# On v26.06 the kernel/soc/firmware are PREBUILT, so install just downloads + assembles the rootfs.
say "build the rootfs image (sshd on, no FDE, user 'user')"
pmbootstrap -y install --password "$PASSWORD" < /dev/null

cat <<EOF

Image built on channel $CHANNEL (kernel: $KERNEL, OpenRC, headless).
Next:  put the phone on the FASTBOOT screen, ./bridge-phone.sh, then ./03-flash-pmos.sh
Login after boot: user 'user' / password '$PASSWORD'  (change it!)
EOF
