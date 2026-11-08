#!/usr/bin/env bash
# Build + (re)deploy the app stack on the phone test-host.
# Runs manually or from the self-hosted GitHub runner (see github-workflow.yml). Idempotent.
#
# Why this isn't just `docker compose up --build`:
#   - the phone's docker has NO bridge, so build RUN steps need --network=host
#     (for npm/apk + to reach a running API during the storefront's sitemap build);
#   - the storefront must build AFTER the API is up (its sitemap.ts fetches it).
#
# Lives in your APP repo (e.g. alongside the app's source). The runner checks out the repo on the
# phone and runs this. App source dirs assumed here: ../medusa (API) and ../nonos (storefront) — rename
# for your app. A failed build leaves the previous containers running, so a bad push won't take the
# site down.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SECRETS=/srv/nono/secrets
SITE="https://shop-dev.example.com"         # public URL (through the Cloudflare Tunnel) for pre-warm
COMPOSE=(docker compose -f "$HERE/compose.yml" --env-file "$SECRETS/nonos.env")

wait_healthy() { # wait_healthy <service> <tries> <sleep>
  local svc="$1" tries="${2:-40}" nap="${3:-3}" cid st
  for _ in $(seq 1 "$tries"); do
    cid="$("${COMPOSE[@]}" ps -q "$svc" 2>/dev/null || true)"
    if [ -n "$cid" ]; then
      st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo starting)"
      [ "$st" = healthy ] && { echo "  $svc: healthy"; return 0; }
    fi
    sleep "$nap"
  done
  echo "  !! $svc did not become healthy in time"; "${COMPOSE[@]}" logs --tail=40 "$svc" || true
  return 1
}

echo "==> [1/6] build API image"
docker build --network=host -t nono/medusa:latest "$ROOT/medusa"

echo "==> [2/6] postgres up"
"${COMPOSE[@]}" up -d postgres
wait_healthy postgres 30 2

echo "==> [3/6] API up (runs DB migrations on boot)"
"${COMPOSE[@]}" up -d medusa
wait_healthy medusa 60 3

echo "==> [4/6] build storefront image (API must be reachable for the sitemap build)"
# pull only the non-secret NEXT_PUBLIC_* lines for build args (never source the whole secret file)
eval "$(grep -E '^NEXT_PUBLIC_(MEDUSA_PUBLISHABLE_KEY|MEDUSA_BASE_URL|R2_BASE|SITE_URL)=' "$SECRETS/nonos.env" || true)"
docker build --network=host \
  --build-arg NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY="${NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY:-}" \
  --build-arg NEXT_PUBLIC_MEDUSA_BASE_URL="${NEXT_PUBLIC_MEDUSA_BASE_URL:-/api/medusa}" \
  --build-arg NEXT_PUBLIC_R2_BASE="${NEXT_PUBLIC_R2_BASE:-}" \
  --build-arg NEXT_PUBLIC_SITE_URL="${NEXT_PUBLIC_SITE_URL:-}" \
  -t nono/web:latest "$ROOT/nonos"

echo "==> [5/6] storefront up"
"${COMPOSE[@]}" up -d storefront
wait_healthy storefront 40 3

echo "==> [6/6] pre-warm image cache at the edge (best-effort, non-fatal)"
# Hit a few pages, extract their /_next/image URLs, and fetch each variant so Cloudflare caches the
# optimized output instead of making the first real visitor wait on the phone's CPU.
if command -v curl >/dev/null 2>&1; then
  n=0
  for p in /ro /ro/shop /en /en/shop; do curl -fsS --max-time 60 "$SITE$p" 2>/dev/null || true; done \
    | grep -oE "/_next/image\?url=[^\"]*w=[0-9]+[^\"]*q=[0-9]+" | sed "s/&amp;/\&/g" | sort -u \
    | while IFS= read -r u; do
        [ -z "$u" ] && continue
        curl -fsS -o /dev/null -H "Accept: image/avif,*/*" --max-time 60 "$SITE$u" 2>/dev/null || true
        curl -fsS -o /dev/null -H "Accept: image/webp,*/*" --max-time 60 "$SITE$u" 2>/dev/null || true
      done
  echo "  pre-warm pass complete"
else
  echo "  curl unavailable; skipping pre-warm"
fi

echo "==> done"
"${COMPOSE[@]}" ps
