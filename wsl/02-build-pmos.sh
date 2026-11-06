#!/usr/bin/env bash
# 02-build-pmos.sh — configure postmarketOS for the OnePlus 5T and build a headless image.
#
# Because the 5T port is ARCHIVED, its kernel is no longer served as a binary, so we build
# it from source first (the recipes still exist in pmaports/device/archived/). This is the
# slow step (~20-40 min, cross-compiled). Everything else is minutes.
set -euo pipefail

DEVICE="oneplus-dumpling"
UI="none"
KERNEL="mainline"          # qcom-msm8998 kernel that actually drives the hardware (not 'alpine')
PASSWORD="${PMOS_PASSWORD:-changeme123}"   # override: PMOS_PASSWORD=... ./02-build-pmos.sh

echo "== pmbootstrap init (non-interactive; -y accepts the 'archived device' prompt) =="
# 40 blank lines = accept all defaults; -y answers the archived/unmaintained confirmation.
printf '%s\n' $(for i in $(seq 1 40); do echo ''; done) > /tmp/pm-init.in || true
yes '' | head -40 > /tmp/pm-init.in
if ! pmbootstrap status >/dev/null 2>&1; then
  printf '\n\noneplus\ndumpling\n\n\nnone\n\n\n\n\n\n\n\n\n\n\n\n\n\n' | pmbootstrap -y init --shallow-initial-clone || true
fi

echo "== force the correct config =="
pmbootstrap config device "$DEVICE"
pmbootstrap config ui "$UI"
pmbootstrap config kernel "$KERNEL"     # 'stable' is INVALID for this device; must be mainline|alpine
pmbootstrap status

echo "== build the archived msm8998 kernel + soc + firmware from source (SLOW) =="
pmbootstrap -y build soc-qcom-msm8998 firmware-oneplus-msm8998 linux-postmarketos-qcom-msm8998

echo "== build the rootfs image (sshd on, no FDE, user 'user') =="
pmbootstrap -y install --password "$PASSWORD"

echo ""
echo "Image built. Next: ./03-flash-pmos.sh  (phone must be on the FASTBOOT screen & bridged)."
