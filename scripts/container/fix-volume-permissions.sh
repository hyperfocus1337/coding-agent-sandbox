#!/usr/bin/env bash
# Chown all named-volume mount targets in the sandbox container back to user:user.
# Fresh Docker named volumes are created root-owned, so the user can't write
# to them until fixed. Targets are read from the compose file so this never drifts
# from the volume list. Runs as root (-u 0) inside the container; no sudo needed.
#
# Run from the repository root via: just fix-volume-permissions
# (COMPOSE below resolves relative to this script's own dir, so it works
# regardless of the working directory).
set -euo pipefail

# Target container and the compose file the volume list is read from.
CONTAINER="coding-agent-sandbox-devcontainer"
COMPOSE="$(dirname "$0")/../../.devcontainer/docker-compose.yml"

# Mount targets of the named (non-bind) volumes: source starts with the project prefix.
mapfile -t targets < <(
    yq -r '.services.sandbox.volumes[]
        | select(test("^coding-agent-sandbox-")) | split(":")[1]' "$COMPOSE"
)

# Bail if the compose file yielded nothing (wrong path, renamed volumes).
[[ ${#targets[@]} -gt 0 ]] || { echo "no named-volume targets found in $COMPOSE" >&2; exit 1; }

# Show what's about to be chowned.
echo "Fixing ownership on ${#targets[@]} volume(s) in $CONTAINER:"
printf '  %s\n' "${targets[@]}"

# chown -R continues past errors but exits non-zero. Read-only bind mounts
# nested in a volume (e.g. the :ro SSH keys under .ssh) are host-owned and
# can't be chowned; those failures are expected. Fail only on anything else.
errs="$(docker exec -u 0 "$CONTAINER" chown -R user:user "${targets[@]}" 2>&1 >/dev/null)" || true
if real="$(grep -v 'Read-only file system' <<<"$errs")" && [[ -n "$real" ]]; then
    echo "$real" >&2
    exit 1
fi
echo "done."
