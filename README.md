# OnePlus 5T → postmarketOS headless server (from Windows + WSL2)

Turn a **OnePlus 5T** (codename `dumpling`, Snapdragon 835) into a small always-on
**Linux server** by flashing **postmarketOS** (bare-metal Alpine/systemd, no Android).

The hard part on Windows is that `fastboot` can't see the phone and **WSL2 has no USB by
default**. The trick used here: **bridge the phone's USB into WSL with `usbipd-win`**, then do
everything from Linux — no Windows driver-signing pain.

> 📌 **Resuming / current status:** see [`docs/HANDOFF.md`](docs/HANDOFF.md) — dense machine-readable
> state. As of 2026-11-06: bootloader unlocked, images build, but **neither kernel boots yet**
> (bootloop); leading cause + next steps are in the handoff.

> ⚠️ **This wipes the phone.** The 5T pmOS port is **archived/unmaintained** — audio is broken
> (fine for a server), Wi‑Fi is unconfirmed (you may need a USB‑C ethernet/Wi‑Fi dongle), and
> there are no upstream updates. See [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

---

## What you need
- OnePlus 5T, USB‑C cable to the laptop.
- Windows 10/11 with **WSL2 (Ubuntu)** whose kernel has the `vhci-hcd` (USB/IP) module
  (standard on recent WSL2 kernels — the scripts check this).
- ~10 GB free disk and some patience (the archived kernel is compiled from source once).

## Order of operations

| Step | Where | Script | What it does |
|------|-------|--------|--------------|
| 1 | **Windows (Admin PowerShell)** | [`windows/install-windows-tools.ps1`](windows/install-windows-tools.ps1) | Installs `fastboot` (platform-tools) + `usbipd-win` |
| 2 | **WSL** | [`wsl/01-install-wsl-tools.sh`](wsl/01-install-wsl-tools.sh) | Installs `fastboot`, the `usbip` client, and `pmbootstrap` (git) |
| 3 | Phone | — | Enable **Developer Options → OEM unlocking** (needed to unlock) |
| 4 | **WSL** | [`wsl/bridge-phone.sh`](wsl/bridge-phone.sh) | Bridges the phone (in **fastboot**) into WSL so Linux `fastboot` sees it |
| 5 | **WSL** | [`wsl/02-build-pmos.sh`](wsl/02-build-pmos.sh) | Configures pmOS, compiles the msm8998 kernel, builds the image |
| 6 | **WSL** | [`wsl/03-flash-pmos.sh`](wsl/03-flash-pmos.sh) | Unlocks bootloader, flashes boot + rootfs, reboots into pmOS |
| 7 | **WSL** | [`wsl/bridge-phone.sh`](wsl/bridge-phone.sh) | Re-bridge the phone's **USB-network** gadget, then `ssh user@172.16.42.1` |

### Quick start
```powershell
# 1) In an ADMIN PowerShell on Windows:
powershell -ExecutionPolicy Bypass -File windows\install-windows-tools.ps1
```
```bash
# 2) In WSL (Ubuntu):
cd ~/oneplus5t-pmos-server/wsl
./01-install-wsl-tools.sh

# 4) Put the phone on the FASTBOOT screen (power off, hold Volume Up + Power), then:
./bridge-phone.sh          # should print "PHONE READY"

# 5) Build the image (compiles the kernel once — slow, ~20-40 min):
./02-build-pmos.sh

# 6) Flash it (wipes phone; you confirm the unlock on the phone screen with Volume+Power):
./03-flash-pmos.sh
```

## Getting in after it boots
postmarketOS (UI=none) comes up **headless** and exposes a **USB-network** interface.
Re-run `./bridge-phone.sh` (it also handles the booted phone), then:
```bash
ssh user@172.16.42.1      # password set during build (default: changeme123 — change it!)
```
From there it's a normal Linux box: `sudo apk add nodejs postgresql …`, and a
[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
gives you a free public HTTPS URL past home CGNAT.

## Why this approach (vs. plain Windows fastboot)
Google's `fastboot` on Windows needs its **Android Bootloader Interface** driver, which does **not**
cover the OnePlus fastboot ID `18d1:d00d`. Binding WinUSB with Zadig makes Device Manager happy but
Google's fastboot still won't talk to it. Bridging the raw USB into WSL and using **Linux fastboot**
sidesteps all of that — Linux just needs the device, no signed driver. See the troubleshooting doc.
