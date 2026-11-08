# 1 · Flash postmarketOS onto the OnePlus 5T

This replaces Android with **postmarketOS v26.06** (mainline kernel, OpenRC, headless). It's written
for the awkward real-world setup where your only machine is **Windows with WSL2**: Windows `fastboot`
can't talk to the OnePlus bootloader, and WSL2 has no USB at all. The trick is to **bridge the
phone's USB into WSL with `usbipd-win`** and flash from Linux `fastboot`.

> ⚠️ **This erases the phone.** The `dumpling` port is archived/unmaintained (audio is broken —
> irrelevant for a server; Wi-Fi *does* work). Don't use a phone you care about.

On a native-Linux host it's simpler — skip the Windows/`usbipd` bridging and run the `wsl/` scripts
directly with the phone plugged in. The steps below assume Windows + WSL2.

---

## What you need

- OnePlus 5T (`dumpling`) + a USB-C **data** cable.
- Windows 10/11 with **WSL2 (Ubuntu)**. Recent WSL2 kernels include the `vhci-hcd` (USB/IP) module the
  scripts rely on; run `wsl --update` if yours doesn't.
- ~10 GB free disk. The build is **fast** (the kernel is a prebuilt binary on v26.06 — no 40-minute
  compile), mostly package downloads.
- About an hour start to finish, most of it unattended.

## The whole flow at a glance

| # | Where | Script | What happens |
|---|-------|--------|--------------|
| 1 | **Windows (Admin PowerShell)** | [`windows/install-windows-tools.ps1`](../../windows/install-windows-tools.ps1) | Installs `fastboot` (platform-tools) + `usbipd-win` |
| 2 | Phone | — | Enable **Developer Options → OEM unlocking** |
| 3 | **WSL** | [`wsl/01-install-wsl-tools.sh`](../../wsl/01-install-wsl-tools.sh) | Installs `fastboot`, the `usbip` client, and `pmbootstrap` (git) |
| 4 | **WSL** | [`wsl/bridge-phone.sh`](../../wsl/bridge-phone.sh) | Bridges the phone (in **fastboot**) into WSL (one UAC click) |
| 5 | **WSL** | [`wsl/02-build-pmos.sh`](../../wsl/02-build-pmos.sh) | Configures pmOS **v26.06 / mainline / OpenRC** and builds the headless image |
| 6 | **WSL** | [`wsl/03-flash-pmos.sh`](../../wsl/03-flash-pmos.sh) | Unlocks the bootloader, flashes `boot` + rootfs, reboots into pmOS |
| 7 | **Windows** | [`windows/setup-usb-network.ps1`](../../windows/setup-usb-network.ps1) | Brings the phone's USB network up on Windows so you can SSH in |

Everything that bit us along the way is in [Troubleshooting](../TROUBLESHOOTING.md).

---

## Step by step

### 1. Windows tools (Admin PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -File windows\install-windows-tools.ps1
```

Installs Google Platform Tools (`fastboot`) and `usbipd-win`. Open a **new** terminal afterwards so
`PATH` updates.

### 2. Unlock permission on the phone

On the phone: **Settings → About phone →** tap *Build number* 7× to enable Developer Options, then
**Developer Options → enable "OEM unlocking"**. (Without this, the unlock in step 6 is refused.)

### 3. WSL tools

```bash
git clone https://github.com/HDorian/phonewslink.git
cd phonewslink/wsl
./01-install-wsl-tools.sh
```

### 4. Bridge the phone (fastboot)

Put the phone on its **fastboot screen**: power it off, then hold **Volume Up + Power**.

> Tip: OnePlus phones **auto-boot when USB power is applied**. If you can't get it to stay off, unplug
> the cable first, force-off (hold Power ~15 s), then Volume Up + Power, and plug back in.

```bash
./bridge-phone.sh      # click YES on the Windows UAC popup; expect "PHONE READY (fastboot)"
```

### 5. Build the image

```bash
./02-build-pmos.sh     # v26.06 + mainline + OpenRC, headless; mostly downloads
```

Default login is `user` / `changeme123` — override with `PMOS_PASSWORD=yourpass ./02-build-pmos.sh`.

### 6. Flash it (wipes the phone)

```bash
./03-flash-pmos.sh
```

The first run triggers the unlock: **watch the phone** — a confirm screen appears, use **Volume** to
highlight *UNLOCK* and **Power** to confirm. The phone wipes and reboots; put it back in fastboot,
re-run `./bridge-phone.sh`, then `./03-flash-pmos.sh` again to flash and reboot into postmarketOS.

### 7. Get in (SSH)

postmarketOS comes up **headless** and offers a network over the USB cable using **RNDIS**. Because
WSL2's kernel can't drive RNDIS but **Windows can natively**, you connect over Windows:

```powershell
# In Windows PowerShell:
powershell -ExecutionPolicy Bypass -File windows\setup-usb-network.ps1
```

It checks the adapter, walks you through the one-time driver assignment if needed, and tells you when
the phone answers. Then, **from a Windows terminal** (not WSL — WSL can't route to this network):

```powershell
ssh user@172.16.42.1          # password: changeme123 (or what you set)
```

You land at a `dumpling:~$` prompt — that's your server. The full why-and-alternatives (static IP,
driving it from WSL via `ssh.exe`, keys) is in **[First access](2-first-access.md)**.

---

## Why bridge USB into WSL instead of using Windows fastboot?

Google's Windows `fastboot` wants its *Android Bootloader Interface* driver, which does **not** match
the OnePlus fastboot USB id `18d1:d00d`, so it shows `< waiting for any device >` forever. Binding
WinUSB with Zadig makes Device Manager look happy but Google's `fastboot` still won't talk to it.
Bridging the raw USB into WSL with `usbipd-win` and using **Linux `fastboot`** sidesteps all of the
driver-signing pain — Linux just needs the device. (Ironically, once pmOS boots, the *network* side is
the opposite: Windows drives RNDIS natively and WSL can't — hence step 7 runs on Windows.)

---

**Next:** **[First access](2-first-access.md)** — the RNDIS/SSH details and how to reach the phone
reliably, then **[Server setup](3-server-setup.md)** to make it a real server.
