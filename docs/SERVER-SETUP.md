# Day 2 — turn the booted phone into a real server

Once postmarketOS boots and you can SSH in (see [`ACCESS.md`](ACCESS.md)), this is how you make it a
proper, standalone server: on **Wi‑Fi** (so the cable is just power), with the **clock synced** and
**Docker** running. Then see [`HARDENING.md`](HARDENING.md) to lock it down.

All commands run **on the phone** (over SSH). `user` can `sudo` with the password you set during the
build.

---

## 1. Wi‑Fi — go standalone (no cable)

Good news that the wiki calls "unconfirmed": **the OnePlus 5T's Wi‑Fi works** on this kernel —
the WCN3990 comes up via `ath10k_snoc` and `wlan0` is present. So the phone can join your network and
you can unplug the USB cable (keep it on a charger for power).

Install NetworkManager and connect:

```sh
sudo apk add networkmanager networkmanager-cli networkmanager-wifi wpa_supplicant

# keep NetworkManager OFF the USB gadget interface (don't let it fight usb0)
printf '[keyfile]\nunmanaged-devices=interface-name:usb0\n' | \
  sudo tee /etc/NetworkManager/conf.d/10-unmanage-usb.conf

sudo rc-update add networkmanager default
sudo rc-service networkmanager start
sleep 5

sudo rfkill unblock wifi
sudo nmcli radio wifi on
sudo nmcli dev wifi connect "YOUR_SSID" password "YOUR_WIFI_PASSWORD" ifname wlan0

ip -4 addr show wlan0      # note the LAN IP it got, e.g. 192.168.0.15
```

NetworkManager saves the connection and **auto-reconnects on every boot**.

### Pin the MAC (important for a stable IP)

This Wi‑Fi chip has **no burned-in MAC**, so the kernel picks a *random* one each boot — which would
break a DHCP reservation. Pin it to the current value so it's stable:

```sh
MAC=$(cat /sys/class/net/wlan0/address)
sudo nmcli connection modify "YOUR_SSID" 802-11-wireless.cloned-mac-address "$MAC"
```

Then, on your router, add a **DHCP reservation** (Address Reservation / Static Lease) mapping that MAC
to the IP you want. Now `ssh user@<that-ip>` always works, cable or not.

> Tip: from WSL you can reach the phone over your LAN directly — add a `~/.ssh/config` entry
> (`Host phone` → `HostName <ip>` → `User user` → `IdentityFile ~/.ssh/id_...`) and just `ssh phone`.

---

## 2. Fix the clock (NTP) — required before Docker

The phone has no RTC, so it **boots at 1970**. That breaks TLS (HTTPS pulls fail with
"certificate is not yet valid"). Install an NTP client:

```sh
sudo apk add chrony
sudo rc-update add chronyd default
sudo rc-service chronyd start
sleep 4 && sudo chronyc makestep      # force an immediate step
date                                  # should now be correct
```

---

## 3. Docker

Docker runs on this phone, but the archived kernel needs three fixes. Install first:

```sh
sudo apk add docker
sudo rc-update add docker default
```

### 3a. cgroups — use **v1 (legacy)**

The daemon won't start until cgroups are mounted, and this kernel has **no `CONFIG_CGROUP_BPF`**, so
cgroup **v2** can't run containers (`runc` fails with `bpf_prog_query(BPF_CGROUP_DEVICE)`). It *does*
have `CONFIG_CGROUP_DEVICE=y`, so **cgroup v1** works. Set legacy mode and reboot:

```sh
echo 'rc_cgroup_mode="legacy"' | sudo tee -a /etc/rc.conf
sudo rc-update add cgroups boot
sudo reboot
```

### 3b. Networking — host mode

Docker's default bridge needs netfilter NAT that this kernel's `iptables` (nf_tables backend) can't
do, so the daemon fails to start with the bridge. Disable Docker's iptables/bridge and use
**host networking** instead:

```sh
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "iptables": false,
  "ip6tables": false,
  "bridge": "none"
}
EOF
sudo rc-service docker restart
```

Run containers with `--network host`; they bind directly on the phone's IP
(e.g. a service on `:9000` is reachable at `<phone-ip>:9000`). Port publishing (`-p`) and
container-to-container bridge DNS are **not** available — host networking is the model here.

### 3c. Use Docker without `sudo`

```sh
sudo addgroup user docker      # then log out/in (or reboot) for the group to take effect
docker run --rm hello-world    # verify
```

You should see **"Hello from Docker!"**. That's a real container running on your phone. 🎉

> The `WARNING: IPv4 forwarding is disabled` message is harmless for host-networked containers.

---

## 4. (Optional) Live status screen on the phone

Nice touch for a headless box sitting on a shelf: turn the phone's screen into an **auto-login
console** showing a status header (battery / CPU / IP / clock) plus a live shell you can drive over
SSH. It uses `tmux` + a bigger console font.

```sh
sudo apk add tmux
# bigger console font (the screen is 1080x2160 — the default 8x16 is tiny)
sudo setfont -C /dev/tty1 /usr/share/consolefonts/ter-132n.psf.gz
```

Autologin `user` on tty1 — edit `/etc/inittab`, change the `tty1` getty line to:

```
tty1::respawn:/usr/bin/login -f user
```

`~/.tmux.conf` (two-line status header that fits the narrow screen):

```tmux
set -g status 2
set -g status-interval 2
set -g status-format[0] "#[bg=colour30,fg=colour231,bold] #H #[default]#[align=right] %a %Y-%m-%d %H:%M:%S "
set -g status-format[1] "#[bg=colour236,fg=colour190,bold] #(/usr/local/bin/tmux-status.sh) "
```

`~/.profile` — on the physical screen only, attach the shared tmux session:

```sh
case "$(tty)" in
  /dev/tty1) command -v tmux >/dev/null && exec tmux new-session -A -s main ;;
esac
```

Put a small `/usr/local/bin/tmux-status.sh` that prints battery/CPU/load/IP (read from
`/sys/class/power_supply/*/capacity`, `/sys/class/thermal/*/temp`, `ip -4 addr`). Then from your
laptop you can drive what shows on the phone screen with:

```sh
ssh user@<phone-ip> 'tmux send-keys -t main "docker ps" Enter'
```

To make the font persist across reboots, add the `setfont` line to `/etc/local.d/` and
`sudo rc-update add local default`.

---

Next: **[HARDENING.md](HARDENING.md)** — keys-only SSH, a working firewall, auto-updates, and Docker
hardening.
