#!/usr/bin/env bash
#
# install.sh <tool> — download and install one binary tool at its pinned version.
#
# Looks up the pinned version in versions.lock and the download recipe (source
# URL, install method, target arch) in manifest.sh, then fetches and installs it.
# Dockerfile.tooling calls this as `install-tool <tool>` (a symlink on PATH).
#
set -euo pipefail

# ── Locate this script ────────────────────────────────────────────────────────
# `install-tool` is a symlink in /usr/local/bin; follow it to the real directory
# so we can source manifest.sh and versions.lock, which sit beside this script.
source_path="${BASH_SOURCE[0]}"
while [ -L "$source_path" ]; do
  link="$(readlink "$source_path")"
  case "$link" in
    /*) source_path="$link" ;;                 # absolute symlink target
    *)  source_path="$(dirname "$source_path")/$link" ;;  # relative to the link
  esac
done
script_dir="$(cd "$(dirname "$source_path")" && pwd)"

# ── Load inputs ───────────────────────────────────────────────────────────────
tool="${1:?usage: install.sh <tool>}"
. "$script_dir/versions.lock"   # pinned versions, e.g. GIT_DELTA_VERSION=0.18.2
. "$script_dir/manifest.sh"     # provides tool_meta / tool_arch

# ── Resolve version, arch, and download URL ───────────────────────────────────
tool_meta "$tool"               # sets METHOD, URL_TMPL, VERSION_VAR, DEST, MEMBER

version="${!VERSION_VAR:-}"
: "${version:?$VERSION_VAR is empty in versions.lock (run 'just lock')}"

arch="$(tool_arch "$tool" "$(dpkg --print-architecture)")"
[ -n "$arch" ] || { echo "Unsupported architecture for $tool" >&2; exit 1; }

url="${URL_TMPL//\{VERSION\}/$version}"   # fill the {VERSION} / {ARCH}
url="${url//\{ARCH\}/$arch}"              # placeholders in the manifest template

# ── Download into a scratch dir (auto-removed on exit) ────────────────────────
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
wget -qO "$tmp/pkg" "$url"
[ -s "$tmp/pkg" ] || { echo "Empty download from $url" >&2; exit 1; }

# ── Install by method ─────────────────────────────────────────────────────────
# deb: system package (root). tar/zip: extract one binary into ~/.local/bin.
case "$METHOD" in
  deb)
    dpkg -i "$tmp/pkg"
    ;;
  tar)
    mkdir -p "$DEST"
    tar -xzf "$tmp/pkg" -C "$DEST" "$MEMBER"
    ;;
  zip)
    mkdir -p "$DEST"
    unzip -q "$tmp/pkg" "$MEMBER" -d "$DEST"
    ;;
  *)
    echo "Unknown install method '$METHOD' for $tool" >&2; exit 1
    ;;
esac

echo "installed $tool $version ($arch)"
