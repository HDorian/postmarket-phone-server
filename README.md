# OnePlus 5T → postmarketOS headless server (Windows + WSL2)

Turn a **OnePlus 5T** (codename `dumpling`, Snapdragon 835 / msm8998) into a small, always-on
**Linux server** by flashing **postmarketOS** — no Android, bare-metal Alpine with OpenRC. You then
reach it headless over SSH and run whatever you like (Docker, a database, a static site, …).

This guide is written for the awkward real-world setup where your only machine is **Windows with
WSL2**: Windows `fastboot` can't talk to the phone's bootloader, and WSL2 has no USB at all. The
trick is to **bridge the phone's USB into WSL with `usbipd-win`** and flash from Linux `fastboot`.

> ✅ **Status: working, end to end.** A OnePlus 5T boots postmarketOS **v26.06** (mainline kernel,
> OpenRC, headless), runs **standalone on Wi‑Fi**, runs **Docker**, and is **hardened** (keys-only
> SSH + `nftables` firewall). It even **hosts real apps**: multiple containers behind a free Cloudflare
> Tunnel (public HTTPS, no open ports) with **`git push` → auto-deploy** via a self-hosted runner, plus
> a live metrics dashboard on its own screen. Flashing is below; turning it into a real server is in
> [`docs/SERVER-SETUP.md`](docs/SERVER-SETUP.md), [`docs/HARDENING.md`](docs/HARDENING.md) and
> [`docs/APP-HOSTING.md`](docs/APP-HOSTING.md).

> ⚠️ **This erases the phone**, and the 5T port is **archived/unmaintained** upstream: audio is
> broken (irrelevant for a server) and there are no more upstream updates. **Wi‑Fi does work**
> (confirmed — so it runs standalone, cable just for power). Don't use a phone you care about, and
> don't leave a phone battery charging 24/7 unattended (swelling/fire risk).

---

## Why postmarketOS (and not Termux/Android)?
A real server workload — **Docker especially** — needs a real Linux kernel with cgroups, namespaces
and overlayfs. Termux/proot **cannot** run Docker. postmarketOS replaces Android with a normal
Alpine userspace on a kernel that supports all of that, which is why it's the target here.

## What you need
- OnePlus 5T + a USB‑C data cable.
- Windows 10/11 with **WSL2 (Ubuntu)**. Recent WSL2 kernels include the `vhci-hcd` (USB/IP) module
  the scripts rely on; `wsl --update` if yours doesn't.
- ~10 GB free disk. The build is **fast** (the kernel is a prebuilt binary on v26.06 — no 40‑minute
  compile), mostly package downloads.
- About an hour start to finish, most of it unattended.

---

## The whole flow at a glance

| # | Where | Script | What happens |
|---|-------|--------|--------------|
| 1 | **Windows (Admin PowerShell)** | [`windows/install-windows-tools.ps1`](windows/install-windows-tools.ps1) | Installs `fastboot` (platform-tools) + `usbipd-win` |
| 2 | Phone | — | Enable **Developer Options → OEM unlocking** |
| 3 | **WSL** | [`wsl/01-install-wsl-tools.sh`](wsl/01-install-wsl-tools.sh) | Installs `fastboot`, the `usbip` client, and `pmbootstrap` (git) |
| 4 | **WSL** | [`wsl/bridge-phone.sh`](wsl/bridge-phone.sh) | Bridges the phone (in **fastboot**) into WSL (one UAC click) |
| 5 | **WSL** | [`wsl/02-build-pmos.sh`](wsl/02-build-pmos.sh) | Configures pmOS **v26.06 / mainline / OpenRC** and builds the headless image |
| 6 | **WSL** | [`wsl/03-flash-pmos.sh`](wsl/03-flash-pmos.sh) | Unlocks the bootloader, flashes `boot` + rootfs, reboots into pmOS |
| 7 | **Windows** | [`windows/setup-usb-network.ps1`](windows/setup-usb-network.ps1) | Brings the phone's USB network up on Windows so you can SSH in |

Full detail on the trickiest part (getting in after boot) is in
[`docs/ACCESS.md`](docs/ACCESS.md). Everything that bit us is in
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

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
cd ~/oneplus5t-pmos-server/wsl
./01-install-wsl-tools.sh
```

### 4. Bridge the phone (fastboot)
Put the phone on its **fastboot screen**: power it off, then hold **Volume Up + Power**.
> Tip: OnePlus phones **auto-boot when USB power is applied**. If you can't get it to stay off,
> unplug the cable first, force-off (hold Power ~15 s), then Volume Up + Power, and plug back in.

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
You land at a `dumpling:~$` prompt — that's your server. See [`docs/ACCESS.md`](docs/ACCESS.md) for
the why and for alternatives (static IP, driving it from WSL via `ssh.exe`, keys).

---

## Day 2 & 3 — make it a real server (and host apps)
Once you're in, change the default password (`sudo passwd user`), then follow:

- **[`docs/SERVER-SETUP.md`](docs/SERVER-SETUP.md)** — join **Wi‑Fi** (go standalone, ditch the
  cable), fix the clock (**NTP** — it boots at 1970, which breaks TLS), install **Docker** with the
  kernel workarounds this archived port needs (cgroup **v1**, host networking), and set up the **live
  split dashboard** on the phone's screen (+ power-button screen toggle).
- **[`docs/HARDENING.md`](docs/HARDENING.md)** — keys-only SSH (+ a source allowlist), a working
  **`nftables`** firewall (the `iptables` shim can't do stateful rules on this kernel — native `nft`
  can), auto-updates, and Docker hardening.
- **[`docs/APP-HOSTING.md`](docs/APP-HOSTING.md)** — host multiple apps (host networking), publish them
  on free **public HTTPS** via a **Cloudflare Tunnel** (no open ports, works behind home CGNAT), and
  get **`git push` → auto-deploy** with a self-hosted GitHub runner on the phone.

---

## Why bridge USB into WSL instead of using Windows fastboot?
Google's Windows `fastboot` wants its *Android Bootloader Interface* driver, which does **not** match
the OnePlus fastboot USB id `18d1:d00d`, so it shows `< waiting for any device >` forever. Binding
WinUSB with Zadig makes Device Manager look happy but Google's `fastboot` still won't talk to it.
Bridging the raw USB into WSL with `usbipd-win` and using **Linux `fastboot`** sidesteps all of the
driver-signing pain — Linux just needs the device. (Ironically, once pmOS boots, the *network* side
is the opposite: Windows drives RNDIS natively and WSL can't — hence step 7 runs on Windows.)

## Repo layout
```
windows/install-windows-tools.ps1   fastboot + usbipd-win
windows/setup-usb-network.ps1       post-boot: RNDIS adapter + SSH reachability
wsl/01-install-wsl-tools.sh         fastboot, usbip client, pmbootstrap
wsl/bridge-phone.sh                 bridge the phone's USB into WSL (fastboot)
wsl/02-build-pmos.sh                configure + build the pmOS image (v26.06)
wsl/03-flash-pmos.sh                unlock + flash + reboot
phone/console/                      live dashboard + power-button screen toggle (runs on the phone)
phone/cloudflared/                  Cloudflare named-tunnel service + config example
phone/runner/                       self-hosted GitHub Actions runner (push-to-deploy)
phone/stack/                        multi-app docker-compose example (host networking)
docs/ACCESS.md                      getting in after boot (RNDIS/SSH), in depth
docs/SERVER-SETUP.md                day 2: Wi-Fi standalone, NTP, Docker, live dashboard
docs/HARDENING.md                   keys-only SSH, nftables firewall, auto-updates, Docker
docs/APP-HOSTING.md                 day 3: multi-app, Cloudflare Tunnel, push-to-deploy
docs/TROUBLESHOOTING.md             every trap we hit, and the fix
```

## Credits
Built on [postmarketOS](https://postmarketos.org/) and
[usbipd-win](https://github.com/dorssel/usbipd-win). The `dumpling` port is community work; it is
archived, so treat this as a best-effort hobby server, not a production platform.
