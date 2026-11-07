#!/bin/sh
# Self-hosted GitHub Actions runner on the phone — the push-to-deploy engine.
#
# Why a container (not the native runner tarball): the official runner is glibc/.NET and fights
# musl on Alpine. A glibc image (this community one) runs it cleanly. It mounts the host docker
# socket (docker-outside-of-docker), so `docker build` / `docker compose` in your workflow run on
# the HOST engine and build natively arm64 — no cloud build, no registry, no open ports (the runner
# dials OUT to GitHub).
#
# One-time setup:
#   1. Create a fine-grained PAT: repo scope = your app repo, permission Administration: Read+write.
#   2. Save it (chmod 600):   echo 'ACCESS_TOKEN=github_pat_xxxxx' > /srv/nono/secrets/runner.env
#      The image mints its own registration tokens from the PAT, so it re-registers on every reboot.
#   3. Run this script. Confirm "Listening for Jobs" in: docker logs nono-runner
#
# SECURITY: runner + docker.sock = root-on-host, and a workflow runs arbitrary code on the phone.
# Use a PRIVATE repo, trigger deploy only on push to main (never fork PRs), and label-scope the job.
set -eu
REPO_URL="https://github.com/<OWNER>/<REPO>"

docker pull myoung34/github-runner:latest
docker rm -f nono-runner 2>/dev/null || true
docker run -d --name nono-runner --restart unless-stopped --network host \
  --env-file /srv/nono/secrets/runner.env \
  -e REPO_URL="$REPO_URL" \
  -e RUNNER_SCOPE=repo \
  -e RUNNER_NAME=nono-phone \
  -e LABELS=nono-phone \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /srv/nono:/srv/nono \
  myoung34/github-runner:latest

echo "started. check:  docker logs -f nono-runner   (want: Listening for Jobs)"
