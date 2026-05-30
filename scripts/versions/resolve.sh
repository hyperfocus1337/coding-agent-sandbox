#!/usr/bin/env bash
# resolve.sh [lockpath]   query upstream "latest" for each tool and rewrite versions.lock.
# Manual dev step (`just lock`); never run during image build.
# Requires: curl, jq.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/manifest.sh"
LOCK_FILE="${1:-$SCRIPT_DIR/../../versions.lock}"

# Fetch the latest tag for a tool given KIND/REPO already set by tool_meta.
latest_tag() {
  case "$KIND" in
    github)
      curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | jq -r '.tag_name' ;;
    gitlab)
      local enc="${REPO//\//%2F}"
      curl -fsSL "https://gitlab.com/api/v4/projects/$enc/releases?per_page=1" | jq -r '.[0].tag_name' ;;
    hashicorp)
      curl -fsSL "https://api.releases.hashicorp.com/v1/releases/terraform/latest" | jq -r '.version' ;;
    *)
      echo "Unknown kind '$KIND'" >&2; return 1 ;;
  esac
}

# Offline self-test stub: returns canned tags so test_versions.sh can verify prefix stripping.
if [ "${RESOLVE_SELFTEST:-0}" = "1" ]; then
  latest_tag() {
    case "$KIND" in
      github)    echo "9.9.9" ;;
      gitlab)    echo "v2.0.0" ;;
      hashicorp) echo "1.99.0" ;;
    esac
  }
fi

emit() {
  local t tag ver
  for t in $ALL_TOOLS; do
    tool_meta "$t"
    tag="$(latest_tag)"
    ver="${tag#"$TAG_PREFIX"}"
    printf '%s=%s\n' "$VERSION_VAR" "$ver"
  done
}

if [ "${RESOLVE_SELFTEST:-0}" = "1" ]; then
  emit
  exit 0
fi

command -v jq >/dev/null || { echo "resolve.sh requires jq" >&2; exit 1; }

# shellcheck disable=SC2016
header='# Pinned versions for binary tools installed in Dockerfile.tooling.
# Single source of truth. Regenerate with `just lock`; edit a line to override.'

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$header" > "$tmp"
emit >> "$tmp"
mv "$tmp" "$LOCK_FILE"
echo "wrote $LOCK_FILE:"
cat "$LOCK_FILE"
