# Troubleshooting & hard-won notes (OnePlus 5T → postmarketOS via WSL)

Everything that bit us, and the fix — so you don't repeat it.

## Choose the right channel: v26.06, NOT edge
The `oneplus-dumpling` port is **archived on edge/main** (no prebuilt binaries there) and an
edge/systemd image **did not boot** on this hardware (frozen logo / bootloop, no USB). On the
**stable `v26.06`** release the port is still live **with prebuilt binaries**, and **v26.06 +
mainline kernel + OpenRC boots**. Takeaways:
- Build on `v26.06`, not edge. The kernel is prebuilt there → **no 40-minute compile**.
- Use **OpenRC** (`pmbootstrap config service_manager openrc`), not systemd.
- In pmbootstrap v3 there is **no `channel` or `systemd` config key**: the channel is the pmaports
  git branch (switched inside `pmbootstrap init`), systemd-vs-openrc is `service_manager`.

## "It flashed but doesn't boot" on edge
If you went down the edge path and saw a frozen OEM logo (no USB) or a bootloop
(logo→black→bootloader→repeat): that's the archived port against bleeding-edge userspace. Don't
debug it — rebuild on `v26.06` as above. `lk2nd` is **not** an option here (pmOS only builds lk2nd
for msm8916/msm8974/msm8226, not msm8998).

## Myth: "`fastboot flash userdata` is a no-op"
The rootfs is an **Android sparse image**. During `fastboot flash userdata`, the real transfer is
the `Sending 'userdata' (... KB) OKAY [10s]` line; the `Writing 'userdata' OKAY [0.005s]` line is
just the final commit. A fast "Writing" time does **not** mean nothing was written. Flashing works
fine; if it doesn't boot, the problem is the kernel/userspace (see channel note), not the flash.

## The phone won't stay off / can't reach the fastboot screen
OnePlus phones **auto-power-on when USB power is applied**. If it's plugged into the laptop, every
power-off instantly reboots. Fix: **unplug the cable**, hold **Power ~15 s** to force off, then hold
**Volume Up + Power** to reach fastboot, then plug back in. (Or just hold **Volume Up** through a
reboot cycle and it drops into fastboot.)

## Windows `fastboot` can't see the phone
OnePlus fastboot enumerates as **`18d1:d00d`**, which isn't in Google's `android_winusb.inf`, so
Google's `fastboot` shows `< waiting for any device >`. Zadig/WinUSB makes Device Manager look OK
but Google's fastboot still won't talk to it. **Fix:** don't fight Windows drivers — bridge the raw
USB into WSL with `usbipd-win` and use **Linux `fastboot`** (`wsl/bridge-phone.sh`).

## `usbipd` elevation / binding
- `usbipd bind` needs Admin; when launched from a WSL-spawned shell, winget/UAC can fail silently.
  Run `windows/install-windows-tools.ps1` in a **real Admin PowerShell**, and let `bridge-phone.sh`
  pop the UAC via `Start-Process -Verb RunAs`.
- `attach` does **not** need Admin; `bind` does. Binding persists per busid.

## WSL has no USB until you load the module
`sudo modprobe vhci-hcd` (the USB/IP virtual host controller). Recent WSL2 kernels ship it; else
`wsl --update`. `bridge-phone.sh` / `01-install-wsl-tools.sh` do this for you.

## Bootloader won't unlock: "Flashing Unlock is not allowed"
Enable **Settings → System → Developer options → "OEM unlocking"** in Android first (tap *Build
number* 7× to reveal Developer options). The 5T uses **`fastboot flashing unlock`**; confirm on the
phone with Volume+Power. It wipes and reboots — get back to fastboot to continue.

## `pmbootstrap init` crashes at "Select a mirror"
On a WSL box with **no IPv6 default route**, pmbootstrap's "best mirror" latency probe dies
(`errno 101 Network unreachable`, or `errno 99 Cannot assign requested address` after disabling
IPv6). This is **harmless** — it's only the interactive probe; `pmbootstrap install` uses the
default mirror and doesn't need it. `02-build-pmos.sh` disables IPv6 for the session and ignores the
init's non-zero exit, then verifies the channel actually switched before building. (If you run init
by hand, just pick a mirror by **number** instead of "best" to skip the probe.)

## `pmbootstrap` version / pmaports clone
- The apt `pmbootstrap` is often too old. Use the **git** version (`01-install-wsl-tools.sh` does
  this): `git clone --depth=1 .../pmbootstrap.git ~/pmbootstrap` + symlink `pmbootstrap.py`.
- Flaky network while cloning pmaports? Use `pmbootstrap init --shallow-initial-clone` and retry;
  disable any VPN. Note `gitlab.postmarketos.org`/`pkgs.postmarketos.org`/`wiki.postmarketos.org`
  301-redirect to `*.nura.eco` — that's the project's hosting, not a hijack.

## "chroot is for channel X but you are on Y"
Switching channels leaves stale chroots. Run `pmbootstrap zap`, or set
`pmbootstrap config auto_zap_misconfigured_chroots yes` (the build script does this) to auto-rebuild.

## Can't reach the phone after it boots (RNDIS)
The USB-net gadget is **RNDIS**, which **WSL can't drive** (no `rndis_host`) but **Windows can**.
Reach it from Windows — see [First access](guides/2-first-access.md). A VPN (e.g. NordVPN) on Windows can interfere
with the `172.16.42.0/24` link; disconnect it if ping/SSH misbehaves.

## Port caveats
- `dumpling` pmOS is **archived/unmaintained**; audio is broken (fine for a server).
- Don't leave a phone battery charging 24/7 unattended (swelling/fire risk).

## Day 2 traps (Wi‑Fi / NTP / Docker / firewall)
Full steps are in [Server setup](guides/3-server-setup.md) and [Hardening](guides/4-hardening.md); these are
the error signatures and quick fixes.

- **Wi‑Fi actually works** (the wiki says "unconfirmed"). `wlan0` comes up via `ath10k_snoc`
  (WCN3990). The chip has **no burned-in MAC** (`dmesg`: "invalid MAC address; choosing random"), so
  pin it with `nmcli ... 802-11-wireless.cloned-mac-address` or DHCP reservations won't stick.
- **TLS / image pulls fail** — "certificate ... is not yet valid: current time 1970-…": the clock is
  at epoch. `apk add chrony` + `chronyc makestep`.
- **dockerd: "Devices cgroup isn't mounted"**: the `cgroups` service isn't running —
  `rc-update add cgroups boot && rc-service cgroups start`.
- **runc: `bpf_prog_query(BPF_CGROUP_DEVICE) failed`** on cgroup v2: this kernel has no
  `CONFIG_CGROUP_BPF`. Use cgroup **v1** — `rc_cgroup_mode="legacy"` in `/etc/rc.conf`, then reboot.
- **dockerd: "failed to register bridge driver … iptables … addrtype … not supported"**: the
  nf_tables `iptables` shim can't do NAT here. Set `"iptables": false`, `"bridge": "none"` in
  `/etc/docker/daemon.json` and use `--network host`.
- **Firewall:** `iptables` (nf_tables backend) can't do `-m conntrack`/`-m addrtype` ("extension …
  not supported"), but the **native `nft` tool can** (`ct state established,related accept` works).
  Use `nftables`, not the `iptables` shim.
