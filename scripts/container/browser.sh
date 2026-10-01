#!/bin/sh
# $BROWSER for the container. No browser runs here, so print each URL for the host
# terminal to open: as an OSC 8 hyperlink (Cmd+click in Ghostty/cmux) when stderr is a
# terminal, as plain text otherwise, so agent tool output stays free of escape codes.
# Writes to stderr because callers such as glab discard the launcher's stdout.
# Exit 0, so the caller waits for its OAuth callback instead of reporting a failure.
for url; do
  if [ -t 2 ]; then
    printf 'Open in your browser: \033]8;;%s\033\\%s\033]8;;\033\\\n' "$url" "$url" >&2
  else
    printf 'Open in your browser: %s\n' "$url" >&2
  fi
done
