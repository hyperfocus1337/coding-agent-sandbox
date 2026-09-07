#!/usr/bin/env bash
# Restart the devcontainer so that it comes back with the current compose config.
#
# Usage: restart.sh <container>
#
# `docker compose restart` is not this. Mounts are baked into a container when it is
# created, so a restarted container never reads a mount that was added since. The only
# ways to apply one are a fresh container, or compose recreating it.
#
# So this converges compose first, which recreates the container when its config
# changed and leaves it alone when it did not. The container id says which happened,
# since the name stays the same. A container that compose rebuilt is already running
# the current config; one it left alone gets `docker restart`.
#
# A container that is stopped, or not there at all, is started: it reads the current
# config either way.
#
# Run from the repository root via: just restart
set -euo pipefail

container="${1?usage: restart.sh <container>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The Justfile owns the compose file list, so the start goes through it. Located from
# this script, so the working directory does not matter.
just() { command just -d "$ROOT" -f "$ROOT/Justfile" "$@"; }

if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)" != true ]]; then
    just up
    exit
fi

before="$(docker inspect -f '{{.Id}}' "$container")"
just up
if [[ "$(docker inspect -f '{{.Id}}' "$container")" != "$before" ]]; then
    exit
fi
docker restart "$container"
