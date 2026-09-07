#!/usr/bin/env bash
# Print the host directory a mounted project comes from, with ${HOME} expanded.
#
# Usage: project-source.sh <project>
#
# <project> is a mounted project, named by its /workspaces directory the way `cas list`
# shows it. Exits 1 when nothing is mounted under that name.
#
# The source is not always named after the project: chezmoi is mounted from
# ~/.local/share/chezmoi. So this is what lets a caller show which directory a rename
# moves, before it moves it.
#
# Run from the repository root via: just project-source <project>
set -euo pipefail

PROG="$(basename "$0" .sh)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

project="${1?usage: $PROG <project>}"

line="$(find_mount "$project")"
from_compose_path "$(line_source "$line")"
