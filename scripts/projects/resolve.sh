#!/usr/bin/env bash
# Resolve a project name to the path it names under /workspaces, and stop it there when
# nothing under it is mounted.
#
# Usage: resolve.sh <container> <target> [<cli>]
#
# The agent recipes do `cd <project>` inside the container. A name that is not mounted
# fails that cd, and the agent then runs in /workspaces, on the whole tree instead of
# the project. Checking first turns that into one message.
#
# <cli> names the front end that message points at: `just` (the default) or `cas`. The
# two have different names for the same two commands, so this is the one place that
# knows both.
#
# add-project mounts the last path segment, so `org/repo` is mounted as
# /workspaces/repo. The same forms are taken here, by dropping leading segments until
# one is a mount: the org dir in `org/repo`, and the whole ~/Repositories prefix in an
# absolute path. So a path that add-project accepts is a path the agents accept.
# Anything after the mount is kept, so `org/repo/src` resolves to `repo/src`.
#
# The leftmost mount wins, so a project named like an org dir still resolves to the path
# that was typed.
#
# Prints the resolved path. Exits 1 when no segment is mounted, or when the listing
# could not be read.
#
# Run from the repository root via: just resolve-project <target>
set -euo pipefail

usage="usage: resolve.sh <container> <target> [<cli>]"
container="${1?$usage}"
target="${2?$usage}"
# The backticks quote a command for the reader, so the hints stay single-quoted
# shellcheck disable=SC2016
if [[ "${3-just}" == cas ]]; then
    prog=cas
    hint='Run `cas list` to see the mounted projects, or `cas add <path>` to mount this one.'
else
    prog=resolve-project
    hint='Run `just projects` to see the mounted projects, or `just add-project <path>` to mount this one.'
fi

# `.` is /workspaces itself, which is the container WORKDIR. `just resume-session` lands
# there on purpose: resuming by id ignores the cwd.
if [[ "$target" == "." ]]; then
    echo .
    exit
fi

projects="$(bash "$(dirname "${BASH_SOURCE[0]}")/list.sh" "$container")"
# Leading and trailing slashes carry no segment
rest="${target#/}"
rest="${rest%/}"
while [[ -n "$rest" ]]; do
    # Compared whole against a line of the listing, so a name that contains a regex
    # character still matches itself and nothing else
    if printf '%s\n' "$projects" | grep -qxF -- "${rest%%/*}"; then
        printf '%s\n' "$rest"
        exit
    fi
    [[ "$rest" == */* ]] || break
    rest="${rest#*/}"
done

echo "$prog: '$target' is not mounted in the container" >&2
echo "$hint" >&2
exit 1
