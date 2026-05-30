# Binary tool version management

The binary CLI tools installed into the tooling image (git-delta, glab, just, just-lsp, terraform) are version-pinned in one place and installed by a shared helper, so a tool's version lives in a single file and its download logic is not duplicated per tool.

## Pieces

| File                           | Role                                                                                                              |
|--------------------------------|-------------------------------------------------------------------------------------------------------------------|
| `versions.lock` (repo root)    | Single source of truth: one `KEY=value` pinned version per tool.                                                  |
| `scripts/versions/manifest.sh` | Static recipe per tool: source API, download URL template, install method, target-arch mapping.                   |
| `scripts/versions/install.sh`  | `install-tool <tool>` — downloads and installs one tool at its pinned version (called from `Dockerfile.tooling`). |
| `scripts/versions/resolve.sh`  | `just lock` — refreshes `versions.lock` with the latest upstream releases.                                        |

## How a build installs a tool

`Dockerfile.tooling` copies `scripts/versions/` and `versions.lock` into the image, symlinks `install.sh` to `/usr/local/bin/install-tool`, then runs e.g.:

```dockerfile
RUN install-tool git-delta
```

`install.sh` reads the pinned version from `versions.lock`, looks up the download recipe in `manifest.sh`, fills the URL template with the version and the build architecture, downloads, and installs by method (`deb` via `dpkg`; `tar`/`zip` extracted into `~/.local/bin`). Builds make no calls to release APIs, so they stay reproducible.

## Pinning, overriding, and updating

- **Override one tool:** edit its line in `versions.lock` and rebuild.
- **Update everything to latest:** run `just lock` (needs `curl` + `jq`), review the `versions.lock` diff, commit. `resolve.sh` queries each tool's release API (GitHub / GitLab / HashiCorp), strips any leading `v`, and rewrites the file.

## Adding a tool

1. Add a `tool_meta` case and a `tool_arch` mapping in `manifest.sh`, and add the tool to `ALL_TOOLS`.
2. Add its `KEY=VERSION` line to `versions.lock` (or run `just lock`).
3. Add `RUN install-tool <tool>` to `Dockerfile.tooling` in the right user context (`deb` tools as root; `tar`/`zip` tools as `$USERNAME`).
