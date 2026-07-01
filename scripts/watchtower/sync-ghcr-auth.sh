#!/usr/bin/env bash
# Watchtower-only Docker config (inline ghcr.io auth; not host osxkeychain).
# Prefers a narrow read:packages PAT ($GHCR_TOKEN) over the broad gh token.
# Idempotent: skips if config.json already has ghcr.io auth (--force to rewrite).
set -euo pipefail

# --- Paths ---
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT}/config/.watchtower-docker"
OUT_FILE="${OUT_DIR}/config.json"

# --- Args ---
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# --- Skip if already present (idempotent) ---
if [[ "$FORCE" -eq 0 && -s "$OUT_FILE" ]] && grep -q '"ghcr.io"' "$OUT_FILE"; then
    echo "ghcr.io auth already present in ${OUT_FILE} — skipping (use --force to rewrite)."
    exit 0
fi

# --- Resolve credential (narrow token preferred) ---
# ponytail: gh can't mint a scoped token; supply $GHCR_TOKEN (a read:packages-only
# PAT) for least privilege, else fall back to the full-scope gh OAuth token.
if [[ -n "${GHCR_TOKEN:-}" ]]; then
    USER="${GHCR_USER:-${USER:-$(id -un)}}"
    TOKEN="$GHCR_TOKEN"
    echo "Using \$GHCR_TOKEN (narrow PAT) for ghcr.io auth."
else
    if ! command -v gh >/dev/null 2>&1; then
        echo "error: gh CLI is required (https://cli.github.com/) or set \$GHCR_TOKEN" >&2
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "error: not logged in to GitHub — run: gh auth login" >&2
        exit 1
    fi

    AUTH_STATUS="$(gh auth status 2>&1)"
    if ! grep -q "read:packages" <<<"$AUTH_STATUS"; then
        echo "warning: gh token lacks read:packages — private GHCR pulls may 403" >&2
        echo "  Run in a terminal (opens browser): gh auth refresh -s read:packages" >&2
        echo "  Then re-run: just sync-watchtower-ghcr-auth" >&2
    fi

    echo "warning: falling back to the full-scope gh token. For least privilege," >&2
    echo "  create a read:packages-only PAT and re-run with GHCR_TOKEN=<pat>." >&2
    USER="$(gh api user -q .login)"
    TOKEN="$(gh auth token)"
fi

# --- Write config.json ---
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
