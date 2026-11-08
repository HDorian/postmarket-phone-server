# `pipeline/` — host apps with `git push` → auto-deploy

The webapp infra: a containerized app on the phone, reachable on **public HTTPS** behind home CGNAT,
that **rebuilds and goes live on its own** a few minutes after you push. All free. The full narrative
walkthrough is in [`../docs/guides/5-app-hosting.md`](../docs/guides/5-app-hosting.md); this folder
holds the concrete, reusable files.

## How it fits together

```
          git push (main)
   you ─────────────────────►  GitHub
                                  │  dispatches job to a self-hosted runner
                                  │  (the runner dialed OUT from the phone — no inbound ports)
                                  ▼
   ┌───────────────────────────  the phone  ───────────────────────────┐
   │  runner container  ──►  deploy.sh                                  │
   │                          • docker build --network=host (arm64)     │
   │                          • compose up -d  (postgres→api→storefront)│
   │                          • pre-warm image cache at the edge        │
   │                                                                    │
   │  stack (host networking):  postgres :5432  api :9000  web :8080    │
   │  secrets: /srv/nono/secrets/*.env  (mounted, never in git)         │
   └───────────────────────────────┬───────────────────────────────────┘
                                    │  cloudflared (outbound tunnel)
                                    ▼
                          Cloudflare edge  ──►  https://shop-dev.example.com
                          (TLS + caches /_next/image, so the phone's CPU is out of the hot path)
```

## What's here

| File | What it is | Where it actually lives in production |
|------|------------|----------------------------------------|
| [`compose.yml`](compose.yml) | The concrete app stack (Postgres + Medusa API + Next.js storefront), host-networking | your **app repo** (e.g. `deploy/compose.yml`) |
| [`deploy.sh`](deploy.sh) | Build (`--network=host`) + ordered `compose up` + edge pre-warm | your **app repo** (e.g. `deploy/deploy.sh`) |
| [`github-workflow.yml`](github-workflow.yml) | The push-to-deploy workflow | your **app repo** at `.github/workflows/deploy.yml` |
| [`compose.multiapp.yml`](compose.multiapp.yml) | A minimal **generic** multi-app template (app + db) to copy for a second app | wherever you keep that app |

The two other moving parts live **on the phone** and are set up from the guides:

- the **runner** — [`../phone/runner/run-runner.sh`](../phone/runner/run-runner.sh) (the push-to-deploy engine)
- the **tunnel** — [`../phone/cloudflared/`](../phone/cloudflared/) (public HTTPS, no open ports)

## The rules that shape all of it

- **Host networking only.** No docker bridge on this kernel → no `-p`, no compose DNS. Each service
  binds `127.0.0.1:<port>`; apps talk to each other via `127.0.0.1:<port>`. "Separation" between apps
  = one compose project each + own named volumes + `mem_limit`/`cpus` caps, *not* kernel isolation.
- **Build with `docker build --network=host`** — build steps otherwise have no network.
- **Secrets stay on the phone** under `/srv/nono/secrets/` and are mounted in; never commit them,
  never bake them into an image. Keep app data in **named volumes** and back them up (e.g. nightly
  `pg_dump` to object storage).
- **Security:** runner + `docker.sock` = **root on the host**, and a workflow runs arbitrary code on
  the phone. Use a **private** app repo, trigger only on push to `main` (never fork PRs), and
  label-scope the job. See [`../docs/guides/4-hardening.md`](../docs/guides/4-hardening.md).

## Adding a second app

Copy [`compose.multiapp.yml`](compose.multiapp.yml), give it its own compose `name:`, its own named
volume(s), and a **unique free port** (storefront `:8080`, API `:9000`, WordPress `:8081`, a static
site `:8082`, …). Add the hostname→port mapping to the cloudflared ingress
([`../phone/cloudflared/config.yml.example`](../phone/cloudflared/config.yml.example)) — not by opening
a firewall port.
