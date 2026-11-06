# Getting in after boot (headless SSH over USB)

postmarketOS here runs **headless** (`ui=none`). You never log in on the phone's screen — that
`dumpling login:` prompt is just a console with no keyboard attached. Instead the phone offers a
**network over the USB cable**, and you SSH to it from your laptop.

## The key fact: it's RNDIS, so you connect from Windows, not WSL

The phone's USB-network gadget comes up as **RNDIS** (`18d1:d001`). Why RNDIS and not something
nicer: the pmOS initramfs tries CDC-**NCM** first and falls back to **RNDIS**, and this port's
mainline **kernel only has `usb_f_rndis` built in** (no `usb_f_ncm`/`ecm`/`eem`/`acm`). So:

| Host | Can it drive the phone's RNDIS gadget? |
|------|----------------------------------------|
| **WSL2** | ❌ No. Its kernel has `cdc_ether`/`cdc_ncm` but **not `rndis_host`**, and you can't easily add a module to the Microsoft WSL kernel. |
| **Windows** | ✅ Yes, natively — RNDIS exists precisely for Windows. |

So the booted phone is reached **from Windows**. (This is the mirror image of flashing, where
Windows couldn't do fastboot and WSL could.)

## Normal path

1. Make sure the phone isn't still bridged into WSL from the flashing step. If `usbipd list` shows
   busid `1-12` (or wherever the phone is) as *Attached*/*Shared*, release it to Windows:
   ```powershell
   usbipd detach --busid <id>
   usbipd unbind --busid <id>   # needs Admin; the bind leaves a stub driver that blocks RNDIS
   ```
2. Run the helper and follow any prompts:
   ```powershell
   powershell -ExecutionPolicy Bypass -File windows\setup-usb-network.ps1
   ```
3. SSH **from a Windows terminal** (PowerShell/Terminal — *not* WSL):
   ```powershell
   ssh user@172.16.42.1        # password from the build (default changeme123)
   ```

## The one-time driver assignment

Linux RNDIS gadgets don't auto-install on Windows — the device shows up in Device Manager as
**"RNDIS"** with a yellow warning / error. Assign the inbox driver manually, once:

1. **Win+X → Device Manager**
2. Find **RNDIS** (under *Other devices*, or *Network adapters*)
3. **Right-click → Update driver → Browse my computer → Let me pick from a list**
4. If asked for a type: **Network adapters**
5. Manufacturer **Microsoft → "Remote NDIS Compatible Device"**
   (fallbacks: *USB RNDIS Adapter*, *Remote NDIS based Internet Sharing Device*)
6. **Next →** accept the warning **→ Close**

The phone now appears as a normal network adapter (e.g. "Ethernet 2") and gets **172.16.42.2** by
DHCP from the phone. Phone = **172.16.42.1**.

## Addresses & DHCP
The phone runs a tiny DHCP server (`unudhcpd`) on the gadget and hands the host **172.16.42.2**. If
Windows doesn't get an address (shows `169.254.x`), set a static one in an **Admin** PowerShell:
```powershell
New-NetIPAddress -InterfaceIndex <ifIndex> -IPAddress 172.16.42.2 -PrefixLength 24
```
(`<ifIndex>` from `Get-NetAdapter`.)

## Driving the phone from WSL (optional, for automation)
WSL can't reach `172.16.42.0/24` directly, but it can call **Windows' `ssh.exe`**, which uses the
Windows network stack:
```bash
/mnt/c/Windows/System32/OpenSSH/ssh.exe user@172.16.42.1 "uname -a"
```
For passwordless automation, generate a key with the Windows `ssh-keygen.exe` (lives in
`%USERPROFILE%\.ssh\id_ed25519`) and append its `.pub` to the phone's `~/.ssh/authorized_keys`
(do that once from an interactive SSH session). Then `ssh.exe user@172.16.42.1` is passwordless from
both Windows and WSL.

## Reliable always-on networking
The USB gadget ties the phone to the laptop. For a standalone box, the robust options are:
- a **USB‑C ethernet dongle** (wired LAN — needs the kernel to support the dongle + USB host mode), or
- **Wi‑Fi**, if it works on this port (unconfirmed; configure via `nmcli`/`wpa_supplicant` once you
  have a shell).
Then a free [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
gives a public HTTPS URL without port-forwarding.

## Heads-up: VPNs
A VPN on Windows (e.g. NordVPN) can add routes/adapters that interfere with the `172.16.42.0/24`
link. If ping/SSH misbehaves, disconnect the VPN and retry.
