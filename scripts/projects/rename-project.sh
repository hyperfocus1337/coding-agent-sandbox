#!/usr/bin/env bash
# Rename a mounted project in both places at once: the directory on the host, and the
# /workspaces name the agents see.
#
# Usage: rename-project.sh <old> <new>
#
# Renaming only one of the two leaves the other pointing at a name that is gone, and
# docker recreates a mount whose source is missing as an empty dir on the host.
#
# <old> is the /workspaces name. <new> is one directory name, not a path: the directory
# keeps its parent. Exits 2 on a bad name, and 1 when <old> is not mounted, <new> already
# is, or the directories are not in the state a rename needs. Nothing is moved or
# rewritten in any of those cases. Applying it is the caller's job, with `just up`.
#
# Run from the repository root via: just rename-project <old> <new>
set -euo pipefail

PROG="$(basename "$0" .sh)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

old="${1?usage: $PROG <old> <new>}"
new="${2?usage: $PROG <old> <new>}"

# --- Check the names ---

# A path would move the repo to another parent, which is not what a rename does
if [[ -z "$new" || "$new" == */* || "$new" == "." || "$new" == ".." ]]; then
    echo "$PROG: the new name must be one directory name, not a path: '$new'" >&2
    exit 2
fi
line="$(find_mount "$old")"
if [[ -n "$(mount_lines "$new")" ]]; then
    echo "$PROG: '$new' is already mounted, so it cannot be the new name" >&2
    exit 1
fi

# --- Check the directories ---

src="$(line_source "$line")"
new_src="$(dirname "$src")/$new"
dir="$(from_compose_path "$src")"
new_dir="$(from_compose_path "$new_src")"
if [[ ! -d "$dir" ]]; then
    echo "$PROG: $dir is not a directory, so there is nothing to rename" >&2
    exit 1
fi
if [[ -e "$new_dir" ]]; then
    echo "$PROG: $new_dir already exists" >&2
    exit 1
fi

# --- Rename ---

mv -- "$dir" "$new_dir"
# The mount points at a path that is gone now, so the rewrite cannot be skipped. Only
# the source and the destination change, so the consistency flag is carried over.
replace_line "$line" "$(mount_line "$new_src" "$new" "$(line_flag "$line")")"
echo "renamed: $old -> $new"
echo "Run \`just up\` to apply it, which recreates the container and kills whatever runs inside."
