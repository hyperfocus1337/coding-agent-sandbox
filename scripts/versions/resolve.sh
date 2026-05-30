#!/usr/bin/env bash
#
# resolve.sh [lockfile] — refresh versions.lock with the latest upstream releases.
#
# Manual maintenance step, run via `just lock`. Queries each tool's release API
# for its newest version and rewrites the lockfile. Never runs during the image
# build — builds read the committed lockfile for reproducibility. Needs curl + jq.
#
set -euo pipefail

# ── Setup ─────────────────────────────────────────────────────────────────────
# Load the manifest (for tool_meta / ALL_TOOLS) and pick the lockfile to write.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/manifest.sh" # provides tool_meta / ALL_TOOLS
lock_file="${1:-$script_dir/../../versions.lock}" # default: repo-root versions.lock

# Fail fast if jq is missing — every release API response below is parsed with it.
command -v jq >/dev/null || { echo "resolve.sh requires jq" >&2; exit 1; }

# ── Fetch the latest release tag for the current tool ─────────────────────────
# KIND/REPO come from tool_meta; each source exposes its version differently.
latest_tag() {
  case "$KIND" in
    github)    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | jq -r '.tag_name' ;;
    gitlab)    curl -fsSL "https://gitlab.com/api/v4/projects/${REPO//\//%2F}/releases?per_page=1" | jq -r '.[0].tag_name' ;;
    hashicorp) curl -fsSL "https://api.releases.hashicorp.com/v1/releases/terraform/latest" | jq -r '.version' ;;
    *)         echo "Unknown kind '$KIND'" >&2; return 1 ;;
  esac
}

# ── Rewrite the lockfile ──────────────────────────────────────────────────────
# Build the new file in a temp, then move it into place atomically. For each
# tool: resolve the latest tag, strip any leading "v", emit KEY=value.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
{
  echo "# Pinned versions for binary tools installed in Dockerfile.tooling."
  echo "# Single source of truth. Regenerate with 'just lock'; edit a line to override."
  for tool in $ALL_TOOLS; do
    tool_meta "$tool"
    tag="$(latest_tag)"
    printf '%s=%s\n' "$VERSION_VAR" "${tag#"$TAG_PREFIX"}"
  done
} > "$tmp"
mv "$tmp" "$lock_file"

echo "wrote $lock_file:"
cat "$lock_file"
