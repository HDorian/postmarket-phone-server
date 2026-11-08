# A dead phone → a self-hosting app server

*A vibecoded project to re-use an old phone as a testing environment. It's driven from **WSL** on
purpose — I'd rather not manage anything from Windows.*

Turn an old **OnePlus 5T** (codename `dumpling`, Snapdragon 835) into a small, always-on **Linux
server** running **postmarketOS** — no Android, bare-metal Alpine with OpenRC. Then run real apps on
it: multiple containers, on **public HTTPS** behind home CGNAT, that **rebuild and go live on their own
a few minutes after `git push`** — plus a live metrics dashboard on the phone's own screen. All on free
tiers, with nothing exposed inbound.

> ✅ **Status: working, end to end.** A OnePlus 5T boots postmarketOS **v26.06** (mainline kernel,
> OpenRC, headless), runs **standalone on Wi-Fi**, runs **Docker**, is **hardened** (keys-only SSH +
> `nftables`), and hosts a containerized web app (Medusa 2 API + Next.js storefront + Postgres) on a
> free **Cloudflare Tunnel** with **push-to-deploy** via a self-hosted runner.

> ⚠️ **This erases the phone,** and the 5T port is **archived/unmaintained** upstream: audio is broken
> (irrelevant for a server) and there are no more upstream updates. **Wi-Fi does work** — it runs
> standalone, cable just for power. Don't use a phone you care about, and don't leave a phone battery
> charging 24/7 unattended (swelling/fire risk).

---

## What you end up with

```
                                      ┌───────────────── the internet ─────────────────┐
                                      │   https://shop-dev.example.com  (your users)    │
                                      └───────────────────────┬─────────────────────────┘
                                                              │  TLS + edge cache (/_next/image)
                                                   Cloudflare edge
                                                              ▲
                                                              │  cloudflared: ONE outbound tunnel
   you ── git push main ──►  GitHub ──┐                       │  (no open ports, CGNAT-proof)
                                      │ dispatch              │
                                      ▼                       │
   ┌──────────────────────────  the OnePlus 5T  ─────────────┴──────────────────────────┐
   │  postmarketOS (Alpine/OpenRC, mainline kernel) · Wi-Fi · hardened (keys-only, nft)  │
   │                                                                                     │
   │  self-hosted runner ──► deploy.sh ──► docker build (arm64) + compose up             │
   │                                                                                     │
   │  Docker (host networking):   postgres :5432   api :9000   storefront :8080          │
   │  secrets on-device: /srv/nono/secrets/*.env       data in named volumes             │
   │                                                                                     │
   │  the phone's own screen: live split dashboard + power-button screen toggle/shutdown │
   └─────────────────────────────────────────────────────────────────────────────────── ┘
```

- **A real server**, not Termux/proot: a proper Linux kernel with cgroups, namespaces and overlayfs,
  so **Docker** actually runs. (Termux can't.)
- **Standalone on Wi-Fi** — the cable is just power. Hardened: keys-only SSH (optional source
  allowlist) and a stateful `nftables` firewall.
- **Push-to-deploy**: a self-hosted GitHub runner on the phone rebuilds + restarts the stack on every
  push to `main`. No cloud build, no registry, no inbound ports.
- **Public HTTPS for free** via a Cloudflare Tunnel, even behind home CGNAT; the edge caches image
  optimization so the phone's CPU stays out of the hot path.
- **A glanceable screen**: a `tmux` split showing CPU/thermal/mem/disk/net/battery + a live container
  list on top and a log stream below, with the power button toggling the panel or cleanly shutting the
  phone down.

## Why postmarketOS (not Termux/Android)?

A real server workload — **Docker especially** — needs a real Linux kernel with cgroups, namespaces and
overlayfs. Termux/proot **cannot** run Docker. postmarketOS replaces Android with a normal Alpine
userspace on a kernel that supports all of that, which is why it's the target here.

---

## The journey (follow in order)

The repo is a field guide as much as a pile of scripts — each step says **why**, not just how.

| # | Guide | You go from → to |
|---|-------|------------------|
| 1 | **[Flash postmarketOS](docs/guides/1-flashing.md)** | stock Android → pmOS booting headless (flash from Windows+WSL via `usbipd`) |
| 2 | **[First access](docs/guides/2-first-access.md)** | booted phone → an SSH shell (the RNDIS-over-USB gotcha, and reaching it reliably) |
| 3 | **[Server setup](docs/guides/3-server-setup.md)** | a shell → Wi-Fi standalone, clock synced, **Docker** running, live dashboard on screen |
| 4 | **[Hardening](docs/guides/4-hardening.md)** | open box → keys-only SSH, `nftables` firewall, auto-updates, locked-down Docker |
| 5 | **[App hosting](docs/guides/5-app-hosting.md)** | a Docker host → multi-app, public HTTPS tunnel, **`git push` → auto-deploy** |

Plus **[Troubleshooting](docs/TROUBLESHOOTING.md)** — every trap we hit (wrong pmOS channel, 1970
clock, cgroup v2, the iptables shim, RNDIS…) and the fix.

## Quickstart (flashing)

On **Windows + WSL2**, with the phone on a USB-C data cable (full detail in
[guide 1](docs/guides/1-flashing.md)):

```powershell
powershell -ExecutionPolicy Bypass -File windows\install-windows-tools.ps1
```

```bash
git clone https://github.com/HDorian/postmarket-phone-server.git
cd postmarket-phone-server/wsl
./01-install-wsl-tools.sh
./bridge-phone.sh      # phone in fastboot (Vol-Up + Power); click YES on the UAC popup
./02-build-pmos.sh     # v26.06 + mainline + OpenRC, headless
./03-flash-pmos.sh     # unlock (confirm on phone) + flash; re-bridge and re-run once to finish
```

```powershell
powershell -ExecutionPolicy Bypass -File windows\setup-usb-network.ps1
ssh user@172.16.42.1   # you're in — now follow guides 3→5
```

On a **native-Linux host** it's simpler: skip the Windows/`usbipd` bridging and run the `wsl/` scripts
directly with the phone plugged in.

---

## Repo layout

```
windows/              flash from Windows: fastboot + usbipd, and the post-boot RNDIS/SSH setup
wsl/                  build + flash from WSL: tools, USB bridge, pmOS build, flash
phone/                everything that runs ON the phone:
  console/              live dashboard + power-button screen toggle / clean shutdown
  cloudflared/          Cloudflare named-tunnel service + config example (public HTTPS)
  runner/               self-hosted GitHub Actions runner (the push-to-deploy engine)
pipeline/             the webapp deploy infra: app stack + deploy.sh + CI workflow + a multi-app template
docs/
  guides/             the step-by-step walkthroughs, in order (1-flashing … 5-app-hosting)
  TROUBLESHOOTING.md  every trap we hit, and the fix
```

## The archived-kernel constraints (read before you extend it)

This port is unmaintained, so a few things differ from a normal server — the guides handle each, but
know them up front:

- **No Docker bridge** (its `nf_tables` NAT matches fail) and **no `/dev/net/tun`** → **host networking
  only**: every container binds `127.0.0.1:<port>`, no `-p`, no compose DNS. Build with
  `docker build --network=host`.
- **cgroup v1** (the kernel has no `CONFIG_CGROUP_BPF`, so v2 can't run containers).
- **`nftables`, not the iptables shim** (the shim can't do stateful/NAT matches here).
- **No RTC** → the phone boots at 1970; sync the clock (`chrony`) before anything does TLS.
- **Headless, no keyboard** → treat every SSH/firewall change as a potential lockout and use the
  self-revert safety pattern in [guide 4](docs/guides/4-hardening.md).

## Security at a glance

Keys-only SSH (no root, no passwords), a default-drop `nftables` firewall (optionally source-allowlisted
to your LAN), nothing exposed inbound (the tunnel dials out), secrets kept on the device under
`/srv/nono/secrets/` and mounted at runtime. **Caveat:** a self-hosted runner with the docker socket is
**root on the host** — use a **private** app repo and trigger only on push to `main`. Details in
[guide 4](docs/guides/4-hardening.md) and [guide 5](docs/guides/5-app-hosting.md).

---

## Beyond the OnePlus 5T

It's built on a 5T, but almost nothing here is 5T-specific: the server, hardening, Docker, tunnel and
push-to-deploy are generic **Alpine/OpenRC + Docker**. Only the flashing scripts and a handful of
kernel workarounds (cgroup v1, host networking, `nftables`) are device-specific. So it can be
**extended to other postmarketOS-supported phones** — if you port it to another device, a PR is very
welcome.

## Contributing & license

Contributions are welcome — porting to other phones, doc fixes, new app recipes. Please read
**[CONTRIBUTING.md](CONTRIBUTING.md)** first: it covers the workflow, **[Conventional
Commits](https://www.conventionalcommits.org/)**, and the archived-kernel constraints to respect. Bugs
and ideas go in the **[issue tracker](../../issues)** (there are templates for bug reports, device
ports, and feature requests). Licensed under the [MIT License](LICENSE).

## Credits

Built on [postmarketOS](https://postmarketos.org/), [usbipd-win](https://github.com/dorssel/usbipd-win),
[cloudflared](https://github.com/cloudflare/cloudflared) and the
[`myoung34/github-runner`](https://github.com/myoung34/docker-github-actions-runner) image. The
`dumpling` port is community work and is archived — treat this as a best-effort hobby server, not a
production platform.
