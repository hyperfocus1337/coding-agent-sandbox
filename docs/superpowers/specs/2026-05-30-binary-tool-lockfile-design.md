# Lockfile-driven binary tool installation

Date: 2026-05-30
Status: approved

## Problem

Five versioned binary tools (git-delta, glab, just, just-lsp, terraform) are installed in
`Dockerfile.tooling`. Each has:

- A pinned version duplicated across **three** places that must be kept aligned manually:
  the Justfile (`*_VERSION :=`), the GitHub workflow (`vars.*` repo variables), and the
  repository variables in GitHub settings.
- Its own ~10-line `RUN` block with duplicated download / arch-case / install / cleanup logic.

This is error-prone (three-way drift) and verbose (5x duplicated download logic).

## Goal

A **lockfile model**: a resolver fetches the latest upstream version on demand and writes a
committed lockfile; builds read the lockfile, so they stay reproducible. Override a tool's
version by editing its entry in the lockfile (edit-only; no env escape hatch). Centralize the
per-tool download/install logic into one shared helper so each Dockerfile `RUN` just names the
tool.

### In scope

The five versioned binary downloads only: git-delta, glab, just, just-lsp, terraform.

### Out of scope (YAGNI)

- corepack pnpm/yarn (`Dockerfile.base`) — already pinned vars, left as-is.
- npm globals (prettier, eslint, markdownlint, codex, gemini, opencode, sandbox-runtime,
  playwright) — left as-is.
- curl|sh installers (starship, claude code, tessl, herdr) and apt installs (gh, opentofu) —
  resolve latest internally; left as-is.
- sha256 / checksum verification — upstream checksum formats vary per tool and current builds
  have none. Can be added later.

## Architecture

Approach B: manifest + shared install helper + version lockfile.

### New files

```
versions.lock                  # repo root. Env-style pinned versions. Resolver-written; edit an entry to override.
scripts/versions/
  manifest.sh                  # static per-tool metadata (sourced, not executable). Edited rarely.
  install.sh                   # install.sh <name>: read manifest+lock, download, install.
  resolve.sh                   # query upstream "latest", rewrite versions.lock.
```

`versions.lock` lives at the repo root (lockfile convention: discoverable alongside other
root config). The manifest and helper scripts live in `scripts/versions/`, a domain subdir
matching the existing `scripts/agents/` layout.

`versions.lock` is the single source of truth for versions. It replaces:

- the `GIT_DELTA_VERSION :=`, `GLAB_VERSION :=`, `JUST_VERSION :=`, `JUST_LSP_VERSION :=`,
  `TERRAFORM_VERSION :=` lines in the Justfile, and
- the `vars.GIT_DELTA_VERSION` / `vars.JUST_VERSION` / `vars.JUST_LSP_VERSION` /
  `vars.TERRAFORM_VERSION` references in the workflow (and the associated "keep aligned"
  comment block).

### `versions.lock` (format)

Env-style `KEY=value`, sourceable by bash and by GitHub Actions:

```sh
GIT_DELTA_VERSION=0.18.2
GLAB_VERSION=1.100.0
JUST_VERSION=1.36.0
JUST_LSP_VERSION=0.3.4
TERRAFORM_VERSION=1.15.3
```

### `scripts/versions/manifest.sh` (schema)

Bash-sourced (no jq/yq dependency). Per-tool fields:

- `kind` — `github` | `gitlab` | `hashicorp`. Drives latest-version lookup in the resolver.
- `repo` — `dandavison/delta`, `gitlab-org/cli`, etc. (n/a for terraform / hashicorp).
- `tag_prefix` — `""` or `v`. Used to build the release tag from the bare version.
- `method` — `deb` | `tar` | `zip`. Install method.
- `url` — download URL template using `${VERSION}` and `${ARCH}`.
- `arch_map` — dpkg arch (`amd64`/`arm64`) → vendor arch string.
- `bin` / `members` — for `tar`/`zip`: member(s) to extract and destination dir.
- `version_var` — the lockfile key (e.g. `GIT_DELTA_VERSION`).

Per-tool values (must reproduce current behavior exactly):

| tool      | kind      | repo             | tag_prefix | method | install ctx | arch_map (amd64 / arm64)                               | extract                     |
|-----------|-----------|------------------|------------|--------|-------------|--------------------------------------------------------|-----------------------------|
| git-delta | github    | dandavison/delta | ""         | deb    | root        | amd64 / arm64 (dpkg arch)                              | n/a                         |
| glab      | gitlab    | gitlab-org/cli   | v          | deb    | root        | amd64 / arm64 (dpkg arch)                              | n/a                         |
| just      | github    | casey/just       | ""         | tar    | user        | x86_64-unknown-linux-musl / aarch64-unknown-linux-musl | `just` → ~/.local/bin       |
| just-lsp  | github    | terror/just-lsp  | ""         | tar    | user        | x86_64-unknown-linux-gnu / aarch64-unknown-linux-gnu   | `./just-lsp` → ~/.local/bin |
| terraform | hashicorp | (n/a)            | ""         | zip    | user        | amd64 / arm64 (dpkg arch)                              | `terraform` → ~/.local/bin  |

URL templates (from current Dockerfile.tooling):

- git-delta: `https://github.com/dandavison/delta/releases/download/${VERSION}/git-delta_${VERSION}_${ARCH}.deb`
- glab: `https://gitlab.com/gitlab-org/cli/-/releases/v${VERSION}/downloads/glab_${VERSION}_linux_${ARCH}.deb`
- just: `https://github.com/casey/just/releases/download/${VERSION}/just-${VERSION}-${ARCH}.tar.gz`
- just-lsp: `https://github.com/terror/just-lsp/releases/download/${VERSION}/just-lsp-${VERSION}-${ARCH}.tar.gz`
- terraform: `https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_${ARCH}.zip`

(`${ARCH}` is resolved via `arch_map`; the deb/zip tools map to bare `amd64`/`arm64`, the tar
tools to the Rust target triple.)

### `scripts/versions/install.sh`

`install.sh <name>`:

1. Source `scripts/versions/manifest.sh` and `versions.lock`.
2. Resolve `VERSION` from the lockfile via `version_var`. Fail loud with a clear message if
   empty (preserves the current `: "${VAR:?...}"` guard intent).
3. Resolve `ARCH` = `arch_map[$(dpkg --print-architecture)]`; unsupported arch → exit 1
   (preserves current `*) echo "Unsupported architecture"` behavior).
4. Expand the URL template. Download to a temp path with `set -eu`; verify the body is
   non-empty (preserves the "invalid URL yields empty body → gzip: unexpected EOF" guard).
5. Install by `method`:
   - `deb` → `dpkg -i` then remove the file.
   - `tar` → `tar -xz` the configured member(s) into the destination dir.
   - `zip` → `unzip -q` the configured member into the destination dir.
   Clean up temp files.

Runs under whichever `USER` the calling `RUN` is in (root for deb tools, `$USERNAME` for the
~/.local/bin tools). The helper does not switch users; the Dockerfile keeps its existing
root / `$USERNAME` section split.

### `scripts/versions/resolve.sh` (`just lock`)

For each tool, look up the latest version by `kind` (uses `curl` + `jq`):

- `github` → `curl https://api.github.com/repos/<repo>/releases/latest` → `.tag_name`. Strip
  `tag_prefix`.
- `gitlab` → `curl .../api/v4/projects/<url-encoded repo>/releases?per_page=1` → `.[0].tag_name`.
  Strip `tag_prefix` (glab's `v`).
- `hashicorp` → `curl https://api.releases.hashicorp.com/v1/releases/terraform/latest` →
  `.version`. (The older `checkpoint.hashicorp.com/v1/check/terraform` endpoint is retired /
  returns 404.)

Rewrite `versions.lock` with the resolved values. No-op (no diff) when already latest. A
`RESOLVE_SELFTEST=1` hook swaps in canned tags so the offline test suite can verify
tag-prefix stripping without network.

**Builds never call the resolver.** It is a manual developer/maintenance step (optionally a
scheduled workflow later). Builds read the pinned `versions.lock`, so they remain reproducible
and make no build-time upstream API calls.

## Dockerfile.tooling changes

Each of the five `RUN` blocks collapses. Example (git-delta):

```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,... install.sh git-delta
```

- `scripts/versions/` and `versions.lock` are `COPY`'d into the image before first use.
- Root-context tools (git-delta, glab) stay under `USER root`; user-context tools (just,
  just-lsp, terraform) stay under `USER $USERNAME`. Section ordering unchanged.
- The existing per-tool `ARG *_VERSION` lines are removed from the Dockerfile (versions now
  come from the lockfile via the helper, not build-args). The helper reads the lockfile that
  is `COPY`'d in.

## Justfile changes

- Remove the five `*_VERSION :=` lines.
- `build-tooling` no longer passes the five `--build-arg *_VERSION`. The lockfile is `COPY`'d
  into the build context and read by the helper inside the image.
- Add a `lock` recipe: `just lock` runs `scripts/versions/resolve.sh`.

## Workflow changes (.github/workflows/docker-devcontainer.yml)

- Remove `GIT_DELTA_VERSION` / `JUST_VERSION` / `JUST_LSP_VERSION` / `TERRAFORM_VERSION` from
  the `build-tooling` `build-args`, and the "keep aligned" comment block referencing repo
  variables.
- No `vars.*` needed for these tools anymore; the lockfile in the repo is authoritative.
- (Repo variables in GitHub settings for these five can be deleted by the maintainer; not a
  code change.)

## Verification

- `just build-tooling` builds clean on `linux/amd64` and `linux/arm64`.
- Inside the image each binary runs: `git-delta --version`, `glab --version`,
  `just --version`, `just-lsp --version`, `terraform version`.
- `just lock` updates `versions.lock` to current upstream latest and is a no-op (no diff)
  when already up to date.
- A bad/empty version in the lockfile fails the build loudly (guard preserved).
```
