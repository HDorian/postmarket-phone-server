# Hardening the phone server

After [Server setup](3-server-setup.md), lock it down. This box is typically **behind your router's
NAT** (not reachable from the internet), so keys-only SSH is the biggest win; the rest is
defense-in-depth.

> ⚠️ **No keyboard = lockout risk.** The phone has no attached keyboard, so a bad SSH or firewall
> change can lock you out with no local recovery. For anything that touches SSH or the firewall,
> apply it with a **self-revert safety**: schedule a rollback in ~90 s unless a *new* connection
> confirms. Pattern:
> ```sh
> ( sleep 90; [ -f /tmp/confirmed ] || { <restore>; <restart service>; }; rm -f /tmp/confirmed ) &
> ```
> Apply the change, open a **fresh** SSH session, and if it works run `touch /tmp/confirmed` to cancel
> the rollback. If it locked you out, the rollback brings it back.

---

## 1. SSH — keys only, no root

You need working key auth first (copy your public key to `~/.ssh/authorized_keys`; both `ed25519`
and `rsa` keys are fine). Then disable passwords with a drop-in:

```sh
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
sudo sshd -t && sudo rc-service sshd restart     # sshd -t validates BEFORE restart
```

Then open a **new** SSH session to confirm your key still gets you in (use the safety pattern above).

---

## 2. Firewall — use native `nftables`, not the iptables shim

Important gotcha on this kernel: the `iptables` command uses the **nf_tables backend**, and its
compatibility shim **can't do stateful (`conntrack`) or NAT matches** here — any `-m conntrack` or
`-m addrtype` rule fails ("extension ... not supported"). But the **native `nft` tool works**,
including `ct state`. So install and use `nftables` directly:

```sh
sudo apk add nftables
sudo tee /etc/nftables.nft >/dev/null <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority filter; policy drop;
    ct state invalid drop
    ct state established,related accept
    iif "lo" accept
    meta l4proto { icmp, icmpv6 } accept
    tcp dport 22 accept
    udp sport 67 udp dport 68 accept      # DHCP client (Wi-Fi)
    udp dport 5353 accept                 # mDNS (optional)
  }
  chain forward { type filter hook forward priority filter; policy drop; }
  chain output  { type filter hook output  priority filter; policy accept; }
}
EOF

# make sure conntrack modules load at boot
for m in nf_conntrack nft_ct; do grep -qx "$m" /etc/modules || echo "$m" | sudo tee -a /etc/modules; done

sudo nft -f /etc/nftables.nft            # apply now (use the safety pattern!)
sudo rc-update add nftables default      # load at boot
sudo rc-service nftables start
```

Confirm it's enforcing: `sudo nft list chain inet filter input` should show `policy drop`, and a fresh
SSH connection still works (that proves the `:22` rule matches on this quirky netfilter).

### Restrict SSH to trusted sources (recommended)

The rule above accepts `:22` from **anywhere**. Tighten it to just your LAN (and optionally a known
remote IP) so the internet can't even reach sshd — replace the `tcp dport 22 accept` line with:

```
ip saddr { 192.168.0.0/24, 203.0.113.7 } tcp dport 22 accept
```

Keep your own subnet in the set or you'll lock yourself out (use the self-revert safety!). This makes
brute-force protection (fail2ban/sshguard) largely redundant — with keys-only auth and a source
allowlist, nothing untrusted can reach the login at all.

### Opening a port for a service

Default-drop means a container service (host networking) **isn't reachable until you open its port**.
Add a line to `/etc/nftables.nft`, e.g. for a service on 9000:

```
tcp dport 9000 accept
```

then `sudo nft -f /etc/nftables.nft`.

---

## 3. Automatic security updates

Alpine has no unattended-upgrades; use `crond` + the periodic hook:

```sh
sudo rc-update add crond default
sudo rc-service crond start
printf '#!/bin/sh\napk update && apk upgrade\n' | sudo tee /etc/periodic/weekly/apk-upgrade
sudo chmod +x /etc/periodic/weekly/apk-upgrade
```

(You're on the **stable** `v26.06` release channel, so these are patch-level updates, not version
jumps.)

---

## 4. Docker hardening

Extend `/etc/docker/daemon.json` (keep the host-networking keys from SERVER-SETUP):

```json
{
  "iptables": false,
  "ip6tables": false,
  "bridge": "none",
  "no-new-privileges": true,
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

`sudo rc-service docker restart`, then `docker info | grep -i "live restore"` to confirm. Also:

- The daemon socket is a **local unix socket** — never expose it over TCP (`-H tcp://…`).
- Run containers as a non-root user (`--user`) where the image allows it.
- `no-new-privileges` is now the default for containers.
- **`docker` group = root.** Anyone who can run `docker` — including a self-hosted CI runner with the
  socket mounted — can mount the host filesystem and become root. Treat socket access as root access:
  trusted users/automation only, and private repos only for any runner (see
  [App hosting](5-app-hosting.md)).

---

## 5. Trim services — carefully

Most of the extra services on a OnePlus 5T are the **Qualcomm radio/remoteproc stack**
(`rmtfs`, `pd-mapper`, `tqftpserv`, `diag-router`, `modem-*`) — **Wi‑Fi firmware loads through
these, so do NOT disable them** or you can lose your only link. Only trim clearly-unrelated ones:

```sh
sudo rc-service q6voiced stop; sudo rc-update del q6voiced    # audio DSP (audio is broken anyway)
```

Keep it minimal; the security benefit is small and the lockout risk (via Wi‑Fi) is real.

---

## Result

Keys-only SSH (no root, no passwords), a stateful `nftables` firewall (default-drop, allowlist),
weekly auto-updates, a locked-down Docker daemon, and a trimmed service set — all persistent across
reboots. Everything above survives a reboot; verify with one (`sudo reboot`) and reconnect.
