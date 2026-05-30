#!/usr/bin/env bash
# Watchtower-only Docker config (inline ghcr.io auth; not host osxkeychain).
set -euo pipefail

# --- Paths ---
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT}/config/.watchtower-docker"
OUT_FILE="${OUT_DIR}/config.json"

# --- Prerequisites ---
if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh CLI is required (https://cli.github.com/)" >&2
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "error: not logged in to GitHub — run: gh auth login" >&2
    exit 1
fi

# --- Scope (warn only; never `gh auth refresh` here — blocks on OAuth) ---
AUTH_STATUS="$(gh auth status 2>&1)"
if ! grep -q "read:packages" <<<"$AUTH_STATUS"; then
    echo "warning: gh token lacks read:packages — private GHCR pulls may 403" >&2
    echo "  Run in a terminal (opens browser): gh auth refresh -s read:packages" >&2
    echo "  Then re-run: just sync-watchtower-ghcr-auth" >&2
fi

# --- Write config.json ---
USER="$(gh api user -q .login)"
TOKEN="$(gh auth token)"
AUTH="$(printf '%s:%s' "$USER" "$TOKEN" | base64 | tr -d '\n')"

mkdir -p "$OUT_DIR"
cat >"$OUT_FILE" <<EOF
{
  "auths": {
    "ghcr.io": {
      "auth": "${AUTH}"
    }
  }
}
EOF
chmod 600 "$OUT_FILE"
echo "Wrote ${OUT_FILE} (inline ghcr.io auth for Watchtower)."
