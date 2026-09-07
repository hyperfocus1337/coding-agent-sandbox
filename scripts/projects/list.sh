#!/usr/bin/env bash
# The mounted projects: the directories under /workspaces in the container.
#
# Usage: list.sh <container>
#
# `ls` sorts, and with no tty it prints one name per line, so this is already the
# listing a caller wants. The container is the source, not the compose override: a mount
# that was added since the container was created is in the override and not in
# /workspaces, and it is the container the agents run in.
#
# Run from the repository root via: just projects
set -euo pipefail

container="${1?usage: list.sh <container>}"
docker exec -u user "$container" ls /workspaces
