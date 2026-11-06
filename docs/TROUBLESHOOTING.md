# Troubleshooting & notes (OnePlus 5T → postmarketOS via WSL)

Everything learned the hard way, so you don't repeat it.

## Windows can't see the phone in fastboot
- OnePlus fastboot enumerates as **`18d1:d00d`**, which is **not** in Google's
  `android_winusb.inf`. Google's `fastboot` wants its *Android Bootloader Interface* driver, so it
  shows `< waiting for any device >` even though the phone is right there.
- Binding **WinUSB with Zadig** makes Device Manager say "OK", but Google's `fastboot` still won't
  talk to it (it needs its own device-interface GUID, which Zadig doesn't provide).
- **Solution used here:** don't fight Windows drivers. Bridge the raw USB into WSL with
  `usbipd-win` and use **Linux `fastboot`**, which only needs the device, no signed driver.

## usbipd-win elevation fails when launched from WSL
- `winget install ... usbipd-win` kicked off from a WSL-spawned shell gets cancelled at UAC
  (exit `1602`) because the elevation prompt doesn't surface. Fixes:
  - Run `windows/install-windows-tools.ps1` **in a real Admin PowerShell**, or
  - Download the MSI and install via `Start-Process msiexec -Verb RunAs -Wait` (explicit UAC).

## WSL has no USB
- `/sys/bus/usb` is absent until you `sudo modprobe vhci-hcd` (the USB/IP virtual host controller).
  Recent WSL2 kernels ship this module; if yours doesn't, `wsl --update`.
- Reconnect flow each session: on Windows `usbipd bind --busid <id>` (admin, once) +
  `usbipd attach --wsl --busid <id>`; in WSL the device then appears. `bridge-phone.sh` automates it.

## Bootloader won't unlock: "Flashing Unlock is not allowed"
- You must first enable **Settings → System → Developer options → "OEM unlocking"** inside Android.
  (Enable Developer options by tapping *Build number* 7× in *About phone*.)
- Then the 5T uses **`fastboot flashing unlock`** (not `oem unlock`). Confirm on the phone with
  Volume+Power. The phone wipes and reboots; get back to fastboot to continue flashing.

## pmbootstrap: "Run pmbootstrap init first" / version too old
- The apt `pmbootstrap` (3.9.0) is too old for current pmaports. Use the **git** version:
  `git clone --depth=1 .../pmbootstrap.git ~/pmbootstrap` and symlink `pmbootstrap.py`.

## pmbootstrap: network reset while cloning pmaports
- `curl 56 Recv failure: Connection reset`. Use `pmbootstrap init --shallow-initial-clone`, retry,
  and consider disabling any VPN (e.g. NordVPN/NordLynx) during the clone. Both
  `gitlab.postmarketos.org` and `wiki.postmarketos.org` 301-redirect to `*.nura.eco` — that's the
  project's hosting, not a hijack.

## The OnePlus 5T port is ARCHIVED (the big caveat)
- `pmbootstrap init` warns "oneplus-dumpling is archived: unmaintained" and the device is dropped
  from the active list. Use `pmbootstrap -y init` to auto-accept the prompt.
- **Kernel binaries were removed from the repo**:
  `apk ... unable to select packages: linux-postmarketos-qcom-msm8998 / soc-qcom-msm8998 /
  firmware-oneplus-msm8998 (no such package)`. The **source recipes still exist** under
  `pmaports/device/archived/`, so build them first:
  `pmbootstrap -y build soc-qcom-msm8998 firmware-oneplus-msm8998 linux-postmarketos-qcom-msm8998`.
- Valid `pmbootstrap config kernel` values for this device: **`mainline`** (qcom-msm8998, use this)
  or `alpine` (generic Alpine kernel — installs without compiling but won't drive the phone's hw).
  The default `stable` is INVALID and errors.

## It flashed but doesn't seem to boot (no USB-network interface)
- The OEM "OnePlus — powered by Android" logo is just the bootloader splash; with a headless kernel
  it can **stay frozen on screen** while Linux boots behind it. The real signal is the
  **USB-network gadget** appearing (SSH at `172.16.42.1`), usually within 1-2 min.
- If **nothing** shows on USB after a few minutes, the kernel likely isn't booting. Options:
  - Test-boot the kernel from RAM: `sudo fastboot boot /tmp/postmarketOS-export/boot.img` and watch
    `usbipd list` / `ip addr` for a new interface.
  - Try the other kernel (`pmbootstrap config kernel alpine`) and rebuild/reflash.
  - Try a **stable release channel** instead of edge (where the archived port may still have had a
    working build): `pmbootstrap config channel <vXX.YY>` then re-init/build. See
    `pmbootstrap.cfg` and `channels.cfg` in pmaports.
  - Because the port is unmaintained, there is no guarantee current edge boots on this device.

## Accessing the server
- Headless pmOS (UI=none) → SSH over the USB-network gadget: `ssh user@172.16.42.1`.
- Wi‑Fi is **unconfirmed** on this port; a **USB-C ethernet/Wi‑Fi dongle** is the reliable way to
  give it real network for an always-on server.
- Public HTTPS past home CGNAT: **Cloudflare Tunnel** (free).
- ⚠️ 24/7 charging a phone battery = swell/fire risk. Don't leave it unattended long-term.
