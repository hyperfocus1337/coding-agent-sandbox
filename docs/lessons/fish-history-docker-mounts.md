# Fish History & Docker Mounts

## The Problem

Fish writes history atomically: it creates a temp file in the **same directory** as the history file, then calls `rename()` to swap it in. If the history file lives on a different filesystem than the temp file, the rename crosses a device boundary and fails:

```
error: Error when renaming history file: Invalid cross-device link
error: Error when renaming history file: Device or resource busy
```

## What Doesn't Work

### Symlinks across mount boundaries

```
~/.local/share/fish/fish_history  →  (symlink)  →  /some-volume/fish_history
                   overlay FS                          Docker named volume
```

Fish creates the temp file in `~/.local/share/fish/` (overlay FS), then tries to rename it to the symlink target on the volume (different device). Kernel rejects it.

### XDG_DATA_HOME redirect

Setting `XDG_DATA_HOME` to a volume path would technically work, but it redirects **all** XDG-compliant apps (npm, cargo, etc.), not just fish.

### Fish's `$fish_history` variable

Controls the history session **name** (e.g. switching between named histories), not the file path. Cannot be used to redirect to an arbitrary location.

## What Works

Mount the named volume **directly at the path fish natively writes to**:

```json
"source=my-fish-history,target=/home/node/.local/share/fish,type=volume"
```

Fish reads and writes `fish_history` entirely within the volume. All temp files and the final rename happen on the same device — no cross-device issue.

## Key Takeaways

- **Never use a symlink to redirect fish history across filesystem boundaries.** Fish's atomic-write strategy is incompatible with cross-device symlinks.
- **Mount the volume at the exact path fish expects.** `~/.local/share/fish` (or `$XDG_DATA_HOME/fish` if XDG is customised) is the right mount target.
- **The volume seeds its ownership from the image directory.** Create `~/.local/share/fish` with correct ownership in the Dockerfile so the volume starts as the right user — no `chown` bootstrap container needed.
