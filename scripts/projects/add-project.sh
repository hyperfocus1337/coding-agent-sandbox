#!/usr/bin/env bash
# Append a project bind mount to the compose override.
#
# Usage: add-project.sh <project> [consistency]
#
# <project> is a path under ~/Repositories (`agents/my-project`) or any absolute path;
# its last segment becomes the /workspaces target. Exits 3 when that mount is already
# there, which is how `cas add` knows there is nothing left to apply. Applying it is the
# caller's job, with `just up`.
#
# Run from the repository root via: just add-project <project> [consistency]
set -euo pipefail

PROG="$(basename "$0" .sh)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

project="${1?usage: $PROG <project> [consistency]}"
consistency="${2:-delegated}"

# --- Resolve the path ---

# A relative path is a repo under ~/Repositories; an absolute one is taken as given, so
# ~/.local/share/chezmoi mounts from where it lives.
project="${project/#\~/$HOME}"
[[ "$project" == /* ]] || project="$HOME/Repositories/$project"
# `cd` settles `.`, `..` and a trailing slash, and fails when the directory is not
# there. Both matter, because neither is an error at `up` time: docker creates a missing
# bind source as an empty dir on the host, and a source of `~/Repositories/.` mounts the
# whole tree onto /workspaces, which then collects one empty dir per sibling mount.
resolved="$(cd -- "$project" 2>/dev/null && pwd)" || {
    echo "$PROG: no such directory: $project" >&2
    exit 1
}
project="$resolved"
# The tree itself is every project at once, and mounting it over /workspaces is the case
# above. Only reachable now by naming it, or as `.` relative to ~/Repositories.
if [[ "$project" == "$HOME/Repositories" ]]; then
    echo "$PROG: $project is the whole repositories tree, not a project" >&2
    exit 2
fi

# --- Append ---

line="$(mount_line "$(to_compose_path "$project")" "$(basename "$project")" "$consistency")"
if grep -qF "$line" "$OVERRIDE"; then
    echo "already mounted: $project"
    exit 3
fi
printf '%s\n' "$line" >>"$OVERRIDE"
echo "mounted: $project"
echo "Run \`just up\` to apply it, which recreates the container and kills whatever runs inside."
