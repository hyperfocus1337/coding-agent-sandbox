#!/usr/bin/env bash
# install.sh <name>            download + install a tool from the manifest at its pinned version
# install.sh --print-url <name>  print the resolved download URL and exit (offline; for tests)
#
# Version comes from versions.lock (override path via VERSIONS_LOCK).
# Arch comes from `dpkg --print-architecture` (override via ARCH_OVERRIDE for tests).
set -euo pipefail

# Resolve this script's real directory even when invoked via a symlink (e.g. /usr/local/bin/install-tool).
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  target="$(readlink "$SOURCE")"
  case "$target" in
    /*) SOURCE="$target" ;;
    *)  SOURCE="$(dirname "$SOURCE")/$target" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

print_url_only=0
if [ "${1:-}" = "--print-url" ]; then print_url_only=1; shift; fi
name="${1:?usage: install.sh [--print-url] <tool-name>}"

# Default: versions.lock colocated with these scripts, as installed in the image via Dockerfile COPY
# (e.g. /usr/local/share/tool-install/versions.lock). Tests and CI supply the repo-root copy via
# the VERSIONS_LOCK env var instead of relying on this default.
LOCK_FILE="${VERSIONS_LOCK:-$SCRIPT_DIR/versions.lock}"
# shellcheck disable=SC1090
. "$LOCK_FILE"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/manifest.sh"

tool_meta "$name"

version="${!VERSION_VAR:-}"
: "${version:?$VERSION_VAR is empty in $LOCK_FILE (set it or run 'just lock')}"

dpkg_arch="${ARCH_OVERRIDE:-$(dpkg --print-architecture)}"
arch="$(tool_arch "$name" "$dpkg_arch")"
[ -n "$arch" ] || { echo "Unsupported architecture '$dpkg_arch' for $name" >&2; exit 1; }

# Expand the template (only ${VERSION} and ${ARCH} are substituted; no eval).
url="${URL_TMPL//\$\{VERSION\}/$version}"
url="${url//\$\{ARCH\}/$arch}"

if [ "$print_url_only" -eq 1 ]; then
  echo "$url"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
file="$tmp/download"

wget -qO "$file" "$url"
[ -s "$file" ] || { echo "Empty download from $url" >&2; exit 1; }

case "$METHOD" in
  deb)
    dpkg -i "$file"
    ;;
  tar)
    mkdir -p "$DEST"
    # shellcheck disable=SC2086
    tar -xzf "$file" -C "$DEST" $MEMBER
    ;;
  zip)
    mkdir -p "$DEST"
    unzip -q "$file" "$MEMBER" -d "$DEST"
    ;;
  *)
    echo "Unknown install method '$METHOD' for $name" >&2; exit 1 ;;
esac

echo "installed $name $version ($arch)"
