#!/bin/bash

set -e

root="${WORKSPACE_FOLDER:-.}"
if [[ ! -d "$root/.tessl" ]]; then
    echo "[tessl.sh] No .tessl directory at $root – skipping." >&2
    exit 0
fi

# Check for updates
tessl outdated

# Install latest Tessl tiles
tessl install --yes --verbose --project-dependencies
