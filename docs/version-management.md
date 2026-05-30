# Binary tool version management

Five CLI tools in the tooling image come as prebuilt release downloads rather than apt packages: **git-delta, glab, just, just-lsp, terraform**. This describes how their versions are pinned and how they get installed.

Out of scope: `PNPM_COREPACK_VERSION` and `YARN_COREPACK_VERSION` are not part of this system. They are still managed in [.github/workflows/docker-devcontainer.yml](../.github/workflows/docker-devcontainer.yml) and the repo Actions variables: <https://github.com/hyperfocus1337/coding-agent-sandbox/settings/variables/actions>.

## The idea

Each tool needs two things: a **version** (which release to grab) and a **recipe** (where to download it and how to install it). We keep those separate:

- The version of every tool lives in one file, `versions.lock`. Change a version in exactly one place.
- The recipe for every tool lives in one file, `manifest.sh`. One small installer script reads both and does the work, so there is no per-tool download code copied around.

Builds only ever read the pinned `versions.lock` (they never call a release API), so an image rebuilt from the same commit installs the same versions.

## Files

| File                           | What it holds                                                                                                                                                                                   |
|--------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `versions.lock` (repo root)    | The pinned version of each tool, one `KEY=value` line (e.g. `JUST_VERSION=1.36.0`), with the tool's releases page linked in a comment above it for manual checking. The single source of truth. |
| `scripts/versions/manifest.sh` | The per-tool recipe: where to fetch it (`KIND`/`REPO`), the download URL template, the install method (`deb`/`tar`/`zip`), and the arch name mapping. Data only, no logic.                      |
| `scripts/versions/install.sh`  | The installer. `install-tool <tool>` downloads and installs one tool at its pinned version. Run during the image build.                                                                         |
| `scripts/versions/resolve.sh`  | The updater. `just lock` rewrites `versions.lock` with the latest upstream releases. Run by hand, never during a build.                                                                         |

## How an install happens

`Dockerfile.tooling` copies `scripts/versions/` and `versions.lock` into the image and exposes the installer on `PATH` as `install-tool`. Each tool is then one line, e.g.:

```dockerfile
RUN install-tool git-delta
```

When that runs, `install.sh`:

1. Reads `GIT_DELTA_VERSION` from `versions.lock`.
2. Looks up git-delta's recipe in `manifest.sh` (URL template, install method, target dir).
3. Fills the `{VERSION}` and `{ARCH}` placeholders in the URL. `{ARCH}` comes from the build's architecture, so the same line works on amd64 and arm64.
4. Downloads the file and installs it: `deb` packages via `dpkg` (as root); `tar`/`zip` archives by extracting the binary into `~/.local/bin`.

## Common tasks

**Pin a tool to a specific version.** Edit its line in `versions.lock` and rebuild. That value wins; `resolve.sh` only changes it if you re-run `just lock`.

**Update everything to the latest releases.** Run `just lock` (needs `curl` + `jq`). It asks each tool's release API (GitHub, GitLab, or HashiCorp) for the newest version, strips any leading `v`, and rewrites `versions.lock`. Review the diff and commit it. Builds stay on the old versions until you do.

**Add a new tool.**

1. In `manifest.sh`: add a `tool_meta` case (its `KIND`, `REPO`, URL template, method, version-var name, extract target) and a `tool_arch` mapping, then add the tool name to `ALL_TOOLS`.
2. In `versions.lock`: add its `KEY=VERSION` line (or just run `just lock`).
3. In `Dockerfile.tooling`: add `RUN install-tool <tool>` in the correct section. `deb` tools run as root; `tar`/`zip` tools run as `$USERNAME` (they install into that user's `~/.local/bin`).
