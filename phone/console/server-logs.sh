#!/bin/bash
# server-logs.sh — live server activity (bottom tmux pane). Ctrl-C drops to a shell.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
CF=/srv/nono/src/deploy/compose.yml
printf '\033[1;32m── live stack activity (Ctrl-C for a shell) ──\033[0m\n'
if [ -f "$CF" ]; then
  docker compose -f "$CF" logs -f --tail=15 2>&1
else
  docker logs -f --tail=15 nonos-web 2>&1
fi
echo "(log stream ended — dropping to shell)"
exec bash
