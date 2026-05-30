#!/usr/bin/env bash
# Offline tests for the versions tooling. No network required.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
check() { # check <label> <actual> <expected>
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1"; echo "  expected: $3"; echo "  actual:   $2"; fail=1
  fi
}

export VERSIONS_LOCK="$DIR/../../versions.lock"

# --- install.sh --print-url must match the URLs currently in Dockerfile.tooling ---
amd64() { ARCH_OVERRIDE=amd64 bash "$DIR/install.sh" --print-url "$1"; }
arm64() { ARCH_OVERRIDE=arm64 bash "$DIR/install.sh" --print-url "$1"; }

check "git-delta amd64 url" "$(amd64 git-delta)" \
  "https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_amd64.deb"
check "glab arm64 url" "$(arm64 glab)" \
  "https://gitlab.com/gitlab-org/cli/-/releases/v1.100.0/downloads/glab_1.100.0_linux_arm64.deb"
check "just amd64 url" "$(amd64 just)" \
  "https://github.com/casey/just/releases/download/1.36.0/just-1.36.0-x86_64-unknown-linux-musl.tar.gz"
check "just-lsp arm64 url" "$(arm64 just-lsp)" \
  "https://github.com/terror/just-lsp/releases/download/0.3.4/just-lsp-0.3.4-aarch64-unknown-linux-gnu.tar.gz"
check "terraform amd64 url" "$(amd64 terraform)" \
  "https://releases.hashicorp.com/terraform/1.15.3/terraform_1.15.3_linux_amd64.zip"

# --- resolve.sh parses stubbed upstream payloads (see Task 4) ---
if [ -f "$DIR/resolve.sh" ]; then
  out="$(RESOLVE_SELFTEST=1 bash "$DIR/resolve.sh" 2>/dev/null || true)"
  check "resolve git-delta" "$(echo "$out" | grep '^GIT_DELTA_VERSION=')" "GIT_DELTA_VERSION=9.9.9"
  check "resolve glab strips v" "$(echo "$out" | grep '^GLAB_VERSION=')" "GLAB_VERSION=2.0.0"
  check "resolve terraform" "$(echo "$out" | grep '^TERRAFORM_VERSION=')" "TERRAFORM_VERSION=1.99.0"
fi

exit $fail
