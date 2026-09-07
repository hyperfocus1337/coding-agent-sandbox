#!/usr/bin/env bash
# Shared helpers for the project mount recipes: add-project, project-source and
# rename-project. Sourced, not run.
#
# Projects reach the container as bind mounts declared in the compose override, one line
# each under services.sandbox.volumes. These functions are the only readers and writers
# of that line, so its format is defined in mount_line below and nowhere else.
#
# Callers resolve their own ROOT and PROG, then source this file next to themselves.

# The file the mounts live in. The Justfile holds the same path as its OVERRIDE
# variable, which is what compose is pointed at.
OVERRIDE="${ROOT}/.devcontainer/docker-compose.override.yml"

# --- The mount line format ---

# One mount line, and the only place the format is written:
#   <indent>- <src>:/workspaces/<name>[:<consistency>]
# The flag is optional, so a line that carries none stays that way through a rename.
mount_line() {
    local src="$1" name="$2" flag="${3-}"
    if [[ -n "$flag" ]]; then
        printf '      - %s:/workspaces/%s:%s\n' "$src" "$name" "$flag"
    else
        printf '      - %s:/workspaces/%s\n' "$src" "$name"
    fi
}

# The source path of a mount line, in the ${HOME} form the override stores
line_source() {
    sed -E 's/^[[:space:]]*-[[:space:]]*//' <<<"${1%%:*}"
}

# The consistency flag of a mount line, empty when it has none
line_flag() {
    cut -d: -f3- <<<"$1"
}

# --- Paths ---

# Compose expands ${HOME} at up time, so a path inside the home dir is stored in that
# form and the override stays portable to a machine with a different home.
# shellcheck disable=SC2016  # ${HOME} is written literally, compose expands it
to_compose_path() {
    case "$1" in
    "$HOME"/*) printf '${HOME}%s\n' "${1#"$HOME"}" ;;
    *) printf '%s\n' "$1" ;;
    esac
}

# The inverse. ${HOME} is expanded by compose, not by the shell, so it has to go before
# a path out of the override names anything on disk.
from_compose_path() {
    printf '%s\n' "${1/#\$\{HOME\}/$HOME}"
}

# --- Lookups ---

# Every mount line whose destination is this /workspaces name.
#
# Matched on the destination field, compared whole: it is the name /workspaces shows, it
# is the one field unique per mount, and an exact compare cannot be fooled by a project
# name that contains a regex character.
mount_lines() {
    awk -F: -v want="/workspaces/$1" '$2 == want' "$OVERRIDE"
}

# The one mount line for a /workspaces name. Prints it, or fails with a message when
# nothing is mounted under that name, or more than one thing is.
find_mount() {
    local name="$1" lines
    lines="$(mount_lines "$name")"
    if [[ -z "$lines" ]]; then
        echo "$PROG: '$name' is not mounted" >&2
        return 1
    fi
    if [[ "$(grep -c '' <<<"$lines")" -gt 1 ]]; then
        echo "$PROG: '$name' is mounted more than once in $OVERRIDE, so fix that first" >&2
        return 1
    fi
    printf '%s\n' "$lines"
}

# --- Writing ---

# Replace one whole line in the override. Read whole, then written back with `>`, which
# truncates the file in place and so keeps its mode.
replace_line() {
    local old="$1" new="$2" contents
    contents="$(awk -v old="$old" -v new="$new" '$0 == old { print new; next } 1' "$OVERRIDE")"
    printf '%s\n' "$contents" >"$OVERRIDE"
}
