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

## 4. Live dashboard on the phone screen

Turn the shelf phone's screen into a **split monitor**: a full metrics panel on top, a live log stream
below — in a shared `tmux` session you can also drive from a laptop. Ready-made scripts are in
[`../phone/console/`](../phone/console).

```sh
sudo apk add tmux bash
# bigger console font (the screen is 1080x2160 -> ~67x67 cells; the default 8x16 is tiny)
sudo setfont -C /dev/tty1 /usr/share/consolefonts/ter-132n.psf.gz
```

Autologin `user` on tty1 — in `/etc/inittab`, set the `tty1` line to:

```
tty1::respawn:/usr/bin/login -f user
```

Install the scripts + config:

```sh
sudo install -m755 phone/console/server-dash.sh phone/console/server-logs.sh /usr/local/bin/
cp phone/console/tmux.conf    ~/.tmux.conf
cp phone/console/profile.tty1 ~/.profile          # rebuilds the split on tty1 login
```

- **`server-dash.sh`** (top pane) — flicker-free full-height panel: uptime + NTP, total + per-core CPU
  with load/freq, every thermal zone, mem/disk bars, live network throughput + TCP count, battery
  volts/amps/watts, a **live auto-enumerated container list** (count + each container's health +
  CPU/mem, from `docker ps`/`inspect` + a backgrounded `docker stats`), and tunnel/runner state.
- **`server-logs.sh`** (bottom pane) — `docker compose logs -f` of your stack (real-time activity;
  Ctrl-C drops to a shell). *Why not a plain shell: your SSH work runs in other shells, invisible here —
  a log stream actually shows what the box is doing.*
- `~/.tmux.conf` sets `status off` (the top pane **is** the header); `~/.profile` builds the 50/50 split
  on login (`new-session … server-dash.sh` + `split-window -v -l 50% … server-logs.sh`).

Drive what's on the phone from a laptop:

```sh
ssh user@<phone-ip> 'tmux send-keys -t main:srv.1 "docker ps" Enter'   # run in the bottom pane
ssh user@<phone-ip> 'tmux attach -t main'                              # or just watch it
```

### Keep the screen on — and toggle it with the power button

The Linux console blanks and the AMOLED panel sleeps, so the screen goes dark. Disable console blanking
at boot, and (nice touch) make the **power button** turn the screen on/off:

```sh
sudo install -m755 phone/console/30-console-unblank.start /etc/local.d/
sudo install -m755 phone/console/screen-toggle.sh phone/console/screen-keepalive.sh \
                   phone/console/powerkey-listen.py /usr/local/bin/
sudo install -m755 phone/console/powerkey.openrc /etc/init.d/powerkey
sudo rc-update add local default      # runs the unblank (+ put your setfont line here too)
sudo rc-update add powerkey default   # python listens on the pwrkey evdev node, toggles the panel
sudo rc-service powerkey start
# keepalive: re-assert the screen ON if it sleeps, UNLESS you pressed power-off (minutely cron)
echo '* * * * * /usr/local/bin/screen-keepalive.sh' | sudo tee -a /etc/crontabs/root
sudo rc-service crond restart
```

`powerkey-listen.py` reads the `pm8941_pwrkey` event node as root and toggles the backlight
(`/sys/class/backlight/*/bl_power` + `brightness`) on each short press; `screen-keepalive.sh` re-asserts
it on if it sleeps on its own but respects a deliberate power-off (tracked in `/run/screen.off`). Add
your `setfont` line to a `/etc/local.d/*.start` script so the big font also survives reboot.

---

Next: **[HARDENING.md](HARDENING.md)** — keys-only SSH, a working firewall, auto-updates, and Docker
hardening.
