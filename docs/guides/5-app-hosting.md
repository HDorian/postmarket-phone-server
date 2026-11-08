# Day 3 — host apps with push-to-deploy + public HTTPS

Once the phone runs Docker ([Server setup](3-server-setup.md)) and is hardened
([Hardening](4-hardening.md)), you can turn it into a real little app host:

- **many apps side by side** (a web app + WordPress + static sites…),
- reachable on a **public HTTPS URL** even behind home CGNAT, and
- **`git push` → it rebuilds and goes live** on its own, in a few minutes.

All free. The pieces are a Docker stack, a Cloudflare Tunnel, and a self-hosted GitHub runner. Example
files live in [`../../phone/`](../../phone).

---

## 1. The one constraint that shapes everything: host networking

This archived kernel can't run Docker's bridge (its `nf_tables` NAT matches fail) and has no
`/dev/net/tun`, so there's **no bridge, no `-p` publishing, no container DNS, no rootless userspace
net**. Every container uses **`network_mode: host`** and binds the host directly on its own port.

So the multi-app model is:

- **one `docker compose` project per app**, each service on a **unique `127.0.0.1:<port>`**;
- apps reach each other and their DBs via `127.0.0.1:<port>` (not service names);
- **"separation" = per-project + own named volumes + `mem_limit`/`cpus` caps** (cgroup v1 works),
  not kernel network isolation. Fine for a personal/test host; know that it isn't a security sandbox.

See [`../../pipeline/compose.multiapp.yml`](../../pipeline/compose.multiapp.yml). Pick a free port per
app (e.g. storefront `:8080`, API/admin `:9000`, WordPress `:8081`, a static site `:8082`).

### Building images on the phone

`docker build` here needs **`--network=host`** — the bridge is off, so otherwise build steps have no
network (can't `npm install`/`apk add`) and can't reach a sibling service during the build. Build
images explicitly, then `compose up` the pre-built images:

```sh
docker build --network=host -t your/app:latest ./app
docker compose -f compose.yml up -d
```

Builds run natively (arm64) and the daemon caches layers, so rebuilds are fast unless deps change.

---

## 2. Public HTTPS — Cloudflare Tunnel (no open ports)

`cloudflared` dials **outbound** to Cloudflare and proxies your `127.0.0.1` services, so **nothing is
exposed inbound** — your firewall stays closed and CGNAT doesn't matter. Free, with TLS + basic
WAF + (optional) Zero-Trust Access in front of admin paths.

```sh
# install the official arm64 binary
sudo wget -qO /usr/local/bin/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
sudo chmod +x /usr/local/bin/cloudflared

cloudflared tunnel login                 # opens a URL; authorize your zone in a browser (one time)
cloudflared tunnel create phone          # writes the tunnel id + <id>.json creds to ~/.cloudflared/
```

Write `~/.cloudflared/config.yml` ([example](../../phone/cloudflared/config.yml.example)) mapping each
hostname to a local port, then create the DNS records:

```sh
cloudflared tunnel route dns phone shop-dev.example.com
cloudflared tunnel route dns phone admin-dev.example.com
```

> This only **adds** the new subdomain CNAMEs (→ `<id>.cfargotunnel.com`, proxied). It never reads or
> changes your apex / `www` / mail records — your existing site is untouched. If you'd rather, add the
> CNAMEs by hand in the Cloudflare DNS dashboard (same target, proxy **on**).

Run it as a service (survives reboot) with
[`../../phone/cloudflared/cloudflared.openrc`](../../phone/cloudflared/cloudflared.openrc):

```sh
sudo install -m755 phone/cloudflared/cloudflared.openrc /etc/init.d/cloudflared
sudo rc-update add cloudflared default
sudo rc-service cloudflared start
```

> ⚠️ **Gotcha:** `output_log` must be writable by the service user. Logging to `/var/log` makes the
> child die on start (the `user` can't create it there) — log under the user's home instead.

Verify from anywhere: `curl -I https://shop-dev.example.com` → `200`, served over Cloudflare's edge.

---

## 3. Push-to-deploy — a self-hosted GitHub runner on the phone

The phone is behind NAT, so use an **outbound** mechanism: a self-hosted Actions runner **on the
phone** that dials out to GitHub, then builds + restarts the stack locally on every push. No cloud
build, no registry, no inbound ports.

Run it with [`../../phone/runner/run-runner.sh`](../../phone/runner/run-runner.sh) (reads a fine-grained
PAT from `/srv/nono/secrets/runner.env`; the container re-registers itself on reboot). Then a minimal
workflow in your app repo:

```yaml
# .github/workflows/deploy.yml
name: deploy
on:
  push: { branches: [main] }
  workflow_dispatch: {}
jobs:
  deploy:
    runs-on: [self-hosted, nono-phone]   # the runner's label
    concurrency: { group: deploy-phone, cancel-in-progress: false }
    steps:
      - uses: actions/checkout@v4
      - run: bash deploy/deploy.sh         # build --network=host, then compose up -d
```

`git push` → the runner checks out `main` → your `deploy.sh` builds + `compose up -d` (+ DB migrations)
→ live in a few minutes. A failed build leaves the old containers running, so a bad push doesn't take
the site down.

> ⚠️ **Security:** runner + `docker.sock` = **root on the host**, and a workflow runs arbitrary code on
> the phone. Use a **private** repo, trigger only on push to `main` (never fork PRs), and keep the PAT
> (`chmod 600`) and app secrets in `/srv/nono/secrets/` — never in the repo or image. Note the same
> boundary means anyone who can run `docker` on the box is effectively root.

### Secrets & data

Runtime secrets (`.env`, keys) live **on the phone** under `/srv/nono/secrets/` and are mounted into
containers — never baked into images or committed. Keep app data in **named volumes** (survive
redeploys) and back them up (e.g. nightly `pg_dump` to object storage).

---

## 4. Images from a CDN, not the phone (optional but worth it)

If an app optimizes images on the fly (e.g. Next.js `/_next/image`), that work runs **on the phone** —
slow on this CPU, and every request hits the box. Two free fixes:

- **Cache the optimizer at the edge:** a Cloudflare **Cache Rule** — *Hostname = your host AND URI Path
  starts with `/_next/image`* → **Eligible for cache**, Edge TTL = *use origin cache-control*. After the
  first request per variant, Cloudflare serves it (`cf-cache-status: HIT`) and the phone is out of the
  loop. Persist the app's on-disk image cache in a volume so it survives redeploys.
- Or serve originals straight from a CDN-backed bucket (e.g. Cloudflare R2's public URL) and skip
  on-the-fly optimization entirely.

---

## Result

A phone that hosts multiple containerized apps on host networking, publishes them on free public HTTPS
through a Cloudflare Tunnel (no open ports), and redeploys itself on `git push` via a self-hosted
runner — with secrets kept on the box and the edge doing the heavy image lifting. Pair it with the live
console dashboard in [Server setup](3-server-setup.md#4-live-dashboard-on-the-phone-screen).
