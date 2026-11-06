# HANDOFF — machine-readable state (OnePlus 5T → postmarketOS)

Dense status for an agent resuming this task. Verify against the live system before acting.
Date: 2026-11-06.

## GOAL
OnePlus 5T as a headless Linux server running **Docker** (host webapps/services).
Constraint: Docker needs real kernel (cgroups/namespaces/overlayfs). proot/Termux CANNOT run
Docker. Options that can: postmarketOS (native, preferred) or QEMU-VM-in-Termux (slow fallback).

## HARDWARE / IDS
- Device: OnePlus 5T, codename `dumpling`, SoC `msm8998` (Snapdragon 835), aarch64, 8GB/128GB.
- Fastboot USB id: `18d1:d00d`. Serial: `308495fb`. usbipd busid (this machine): `1-12` (persisted+shared).
- Bootloader: **UNLOCKED** (`fastboot getvar unlocked` = yes). OEM-unlock toggle already enabled.

## ENVIRONMENT (already set up)
- Host: Windows 10/11 + WSL2 Ubuntu. WSL2 has NO USB natively → bridged via usbipd-win.
- Windows: `Google.PlatformTools` (fastboot) + `usbipd-win` 5.3.0 installed. usbipd.exe at
  `C:\Program Files\usbipd-win\usbipd.exe`.
- WSL: `fastboot` (1:34), usbip client (`/usr/local/bin/usbip` via linux-tools), `pmbootstrap`
  from GIT = **3.12.1** at `/usr/local/bin/pmbootstrap -> ~/pmbootstrap/pmbootstrap.py`
  (apt's 3.9.0 was too old; removed).
- pmbootstrap workdir: `~/.local/var/pmbootstrap/`. cfg: `~/.config/pmbootstrap_v3.cfg`.
  pmaports (shallow, main/edge): `~/.local/var/pmbootstrap/cache_git/pmaports/`.

## RECONNECT THE PHONE EACH SESSION (phone on FASTBOOT screen)
Run `~/phone-fastboot.sh` (or repo `wsl/bridge-phone.sh`): modprobe vhci-hcd → usbipd
bind(if needed, UAC)+attach --wsl → `sudo fastboot devices` shows `308495fb fastboot`.

## WHAT WAS BUILT (both compiled locally; device is ARCHIVED so NO prebuilt binaries exist)
- pmbootstrap config: channel `systemd-edge`, `ui=none`, `systemd=yes`.
- Kernel A (mainline): `linux-postmarketos-qcom-msm8998` 6.0-r3 + soc-qcom-msm8998 +
  firmware-oneplus-msm8998. device=`oneplus-dumpling`, kernel=`mainline`.
- Kernel B (downstream/vendor): `linux-oneplus-msm8998-downstream` 4.4.217 (needs gcc6; auto).
  device=`oneplus-dumpling-downstream` (its own codename; single kernel, `config -r kernel`).
- Build cmds: `pmbootstrap -y build <pkgs>` then `pmbootstrap -y install --password changeme123`
  (sshd on, no FDE, user=`user`). Export images: `pmbootstrap export` → `/tmp/postmarketOS-export/`
  (`boot.img` + `<codename>.img`).

## FLASH METHOD USED
```
sudo fastboot flash boot /tmp/postmarketOS-export/boot.img
sudo fastboot flash userdata /tmp/postmarketOS-export/<codename>.img
sudo fastboot reboot
```
Access after boot (expected): `ssh user@172.16.42.1` pw `changeme123` (USB-net gadget).

## CURRENT BLOCKER — NEITHER KERNEL BOOTS
- Mainline flashed: phone sits on frozen OnePlus logo, **no USB gadget in 150s** (RAM-boot test
  `fastboot boot boot.img` = "Booting OKAY" then nothing) → kernel dies before USB.
- Downstream flashed: **BOOTLOOP** (OnePlus logo → black → bootloader → repeat), no USB.

## LEADING HYPOTHESIS (verify first)
`fastboot flash userdata` is likely a **silent NO-OP on this device** (known OnePlus msm8998 quirk):
flash reported `Writing 'userdata' OKAY [0.021s]` for a 187MB image — far too fast = nothing
written. If rootfs never lands, kernel boots then panics (no root) → bootloop. This fits both failures.

## NEXT STEPS (ordered)
1. Phone→fastboot, `~/phone-fastboot.sh`. Check: `sudo fastboot getvar partition-size:userdata`.
2. Test the no-op: `sudo fastboot erase userdata` then re-flash userdata; watch if "Writing" takes
   realistic time (~10s+). Try `sudo fastboot flash -S 100M userdata <img>` (force sparse chunks).
3. If fastboot userdata truly won't write: flash rootfs via a booted recovery (TWRP for dumpling)
   + `adb push` + `dd`, or `simg2img` then dd. OR get pmOS initramfs USB-debug up to dd remotely.
4. lk2nd: msm8998 devices often need/benefit from lk2nd. Try `fastboot flash boot lk2nd.img`
   (build/get lk2nd for msm8998), then it chainloads the pmOS boot. See wiki Template:Lk2nd.
5. If kernel panics BEFORE initramfs (no USB-debug ever): suspect DTB/cmdline mismatch in boot.img
   — check `deviceinfo` offsets; try mainline vs downstream cmdline.
6. Alt channel: stable `v26.06` (recommended, OpenRC). Requires re-init (channel switch) + recompile.
   Channels in `pmaports/channels.cfg`. NOTE edge forces systemd for ui=none; stable has openrc ui-none.
7. FALLBACK (guaranteed Docker, no boot fight): QEMU-Linux-VM in Termux on Android. BUT userdata now
   holds pmOS rootfs — must restore Android first (OxygenOS fastboot ROM / MSM Download Tool).

## NOTES
- Wiki `wiki.postmarketos.org`/`gitlab.postmarketos.org` 301→`*.nura.eco` (pmOS infra, not hijack);
  wiki device page is behind Anubis bot-protection (can't WebFetch; open in a browser).
- Caveats: dumpling pmOS = archived/unmaintained; audio broken (ok for server); Wi-Fi unconfirmed
  (may need USB-C ethernet/Wi-Fi dongle); 24/7 charge = battery swell risk.
- Repo: github.com/HDorian/phonewslink. Local: ~/oneplus5t-pmos-server. SSH key id_ed25519 = HDorian.
