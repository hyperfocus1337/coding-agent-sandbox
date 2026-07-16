#!/bin/sh
# Container entrypoint: seed the node user's sudo password from a runtime-mounted
# file (never baked into the image), then run the container command as node.
#
# The password file is bind-mounted read-only at /root/.sudo-password via
# .devcontainer/docker-compose.override.yml. /root is mode 0700, so the node user
# — and any agent running as node — cannot read the plaintext; only this entrypoint,
# which runs as root, can. If no file is mounted (published images, other users who
# skip it) sudo stays locked, exactly as if no password were ever set.
#
# CR/LF is stripped so a CRLF-saved file does not bake a stray \r into the password.
set -eu

seed=/root/.sudo-password
if [ -s "$seed" ]; then
    printf 'node:%s\n' "$(tr -d '\r\n' <"$seed")" | chpasswd
fi

# Drop root and run the container command (compose `command:`, e.g. sleep infinity) as node.
exec runuser -u node -- "$@"
