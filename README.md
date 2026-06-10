# Dev Container

This directory defines a [Dev Container](https://containers.dev/) environment for any coding agent project.

## Contents

### Images

| Path                    | Description                                                                                                                                                                                                                                                                                                                                                                                                                  |
|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Dockerfile.base`       | Base image on [`node:26-trixie`](https://github.com/nodejs/docker-node/tree/main/26/trixie). OS apt packages (baseline shell/dev tools plus an AI-agent CLI toolkit — ripgrep, fd, bat, yq, …; see [apt packages](#apt-packages-dockerfilebase)), Starship, Corepack (pnpm/yarn), SSH + sudo bootstrap, default editor, permissions — **no developer tooling, no Python**. Consume this for a minimal Node + shell baseline. |
| `Dockerfile.tooling`    | Child image on top of `devcontainer-base`: general developer tooling (GitHub CLI, git-delta, `just`, just-lsp) then AI tooling (Anthropic sandbox-runtime, Claude Code, Codex, Gemini, OpenCode, Tessl, Claude plugins/MCP). `BASE_IMAGE` selects the base (default `…/devcontainer-base:latest`; CI pins digest after push).                                                                                                |
| `Dockerfile.python`     | Child image on top of `devcontainer-tooling`: adds `python3` + `uv`. `BASE_IMAGE` selects the base (default `…/devcontainer-tooling:latest`; CI pins digest after push).                                                                                                                                                                                                                                                     |
| `Dockerfile.playwright` | Child image on top of `devcontainer-python`: Playwright system deps and Chromium (`PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`). `BASE_IMAGE` selects the base (default `…/devcontainer-python:latest`; CI pins digest after push).                                                                                                                                                                                             |

### apt packages (`Dockerfile.base`)

`Dockerfile.base` installs OS packages in two logical `apt-get` blocks. Grouping lives here in the docs, not in extra Docker layers: each block is one layer + one `apt-get update`, and the more frequently edited AI-agent block sits last so changing it never rebuilds the baseline layer.

**Baseline** — general shell + dev essentials:

| Package             | Provides          | Purpose                                          |
|---------------------|-------------------|--------------------------------------------------|
| `less`              |                   | pager                                            |
| `git`               |                   | version control                                  |
| `procps`            | `ps`, `top`       | process inspection                               |
| `sudo`              |                   | privilege escalation (see sudo password section) |
| `fzf`               |                   | fuzzy finder                                     |
| `fish`              |                   | default interactive shell                        |
| `man-db`            | `man`             | manual pages                                     |
| `unzip`             |                   | archive extraction                               |
| `ca-certificates`   |                   | TLS root certs                                   |
| `curl` / `wget`     |                   | HTTP download                                    |
| `gnupg` / `gnupg2`  | `gpg`             | signature/key handling                           |
| `dnsutils`          | `dig`, `nslookup` | DNS debugging                                    |
| `jq`                |                   | JSON processor                                   |
| `tree`              |                   | directory tree view                              |
| `neovim`            | `nvim`            | default editor (`EDITOR`/`VISUAL`)               |
| `direnv`            |                   | per-directory env loading                        |
| `postgresql-client` | `psql`            | Postgres CLI                                     |

**AI-agent tooling** — utilities coding agents shell out to, pinned so they are always present:

| Package           | Provides                        | Purpose                                                                                   |
|-------------------|---------------------------------|-------------------------------------------------------------------------------------------|
| `ripgrep`         | `rg`                            | fast recursive grep; Claude Code's search backend                                         |
| `fd-find`         | `fd` (symlinked from `fdfind`)  | fast file finder                                                                          |
| `bat`             | `bat` (symlinked from `batcat`) | `cat` with syntax highlight + line numbers                                                |
| `shellcheck`      |                                 | shell script linter                                                                       |
| `universal-ctags` | `ctags`                         | symbol/tag indexing for code nav                                                          |
| `patch`           |                                 | apply unified diffs                                                                       |
| `patchutils`      | `filterdiff`, `interdiff`, …    | manipulate patches                                                                        |
| `miller`          | `mlr`                           | CSV/TSV/JSON stream processor                                                             |
| `csvkit`          | `csvlook`, `csvcut`, …          | CSV toolkit                                                                               |
| `httpie`          | `http`, `https`                 | friendly HTTP client                                                                      |
| `netcat-openbsd`  | `nc`                            | TCP/UDP socket tool                                                                       |
| `socat`           |                                 | bidirectional socket relay                                                                |
| `lsof`            |                                 | list open files / ports                                                                   |
| `file`            |                                 | detect file type by content                                                               |
| `moreutils`       | `sponge`, `ts`, `chronic`, …    | extra Unix utilities                                                                      |
| `ncdu`            |                                 | interactive disk usage browser                                                            |
| `strace`          |                                 | trace syscalls / signals                                                                  |
| `rsync`           |                                 | fast incremental file sync                                                                |
| `yq`              | `yq`                            | YAML/TOML/XML processor — installed as a pinned static binary (`YQ_VERSION`), not via apt |

### Configuration and scripts

| Path                       | Description                                                                                            |
|----------------------------|--------------------------------------------------------------------------------------------------------|
| `.devcontainer/`           | VS Code / Cursor Dev Container configuration (optional; this repo often gitignores this tree locally). |
| `config/config.fish`       | Fish shell configuration (Starship prompt, direnv hook, PATH).                                         |
| `scripts/agents/claude.sh` | Installs Claude Code plugins and MCP servers (Context7, Tessl, GitHub).                                |
| `scripts/agents/gemini.sh` | Gemini CLI extensions (CLI is installed in `Dockerfile.tooling`; this script is commented out there).  |
| `Justfile`                 | Convenience commands for building the images and common container tasks.                               |

### Docs and version pinning

| Path                             | Description                                                                                                                                                   |
|----------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `docs/sharing-claude-history.md` | Notes for migrating Claude Code conversation history across machines or Docker volumes.                                                                       |
| `docs/version-management.md`     | How binary tool versions are pinned in `versions.lock`, updated (`just lock`), and installed during the image build.                                          |
| `versions.lock`                  | Pinned versions for prebuilt binary tools in `Dockerfile.tooling` (git-delta, glab, just, just-lsp, terraform). Single source of truth — not duplicated here. |

## Justfile

Run `just` from the **repository root** (where `Dockerfile.base` and `Justfile` live).

### Build the images

```bash
just build
```

This runs **`build-base`** → **`build-tooling`** → **`build-python`** → **`build-playwright`**, producing four images tagged with `VERSION` (default `local`) and `latest`:

- `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base:{VERSION,latest}`
- `…/devcontainer-tooling:{VERSION,latest}`
- `…/devcontainer-python:{VERSION,latest}`
- `…/devcontainer-playwright:{VERSION,latest}`

#### Building a single layer

Use **`just build-base`**, **`just build-tooling`**, **`just build-python`**, or **`just build-playwright`** alone when you only need one layer (for example, after pulling a published parent from GHCR).

#### Selecting the base image

`Dockerfile.tooling`, `Dockerfile.python`, and `Dockerfile.playwright` accept **`BASE_IMAGE`** (must match the layer you extend). The recipes wire each child to the prior layer's `:latest` tag locally so overrides to `IMAGE_BASE`/`IMAGE_TOOLING`/`IMAGE_PYTHON` still stack.

#### Corepack and binary tool versions

`Dockerfile.base` does **not** embed Corepack semver in the Dockerfile; `just build` and CI pass `PNPM_COREPACK_VERSION` and `YARN_COREPACK_VERSION` as build args. `Dockerfile.tooling` installs prebuilt binary tools via `install-tool`, reading pinned versions from `versions.lock`. See [docs/version-management.md](docs/version-management.md) for pinning, updating (`just lock`), and adding tools.

#### GitHub Actions builds

In **GitHub Actions** (`.github/workflows/docker-devcontainer.yml`), four independent jobs (`build-base`, `build-tooling`, `build-python`, `build-playwright`) each build and push their own image to GHCR with metadata-driven tags (branch, PR, semver, SHA, `latest` on the default branch). Each job is a separate runner — `devcontainer-base` is pushed and pullable the moment its job finishes, regardless of whether the downstream `tooling`/`python`/`playwright` jobs are still running or have failed. Downstream jobs pin **`BASE_IMAGE`** to the upstream **digest** so child images match exactly. On **pull requests** images are not pushed, so the downstream jobs fall back to the parent's `:latest` tag on GHCR for Dockerfile validation.

Repository **Actions variables** supply `PNPM_COREPACK_VERSION` and `YARN_COREPACK_VERSION` for CI (**Settings → Secrets and variables → Actions → Variables**). Locally, `just build` reads them from the environment. Binary tool versions are not build-args — edit `versions.lock` or run `just lock` instead.

#### SSH client config

SSH client config uses the optional BuildKit secret `ssh_config` (same mechanism locally and in GitHub Actions: repo secret `SSH_CONFIG` → `secret-files`). If the secret is missing or empty, the image is built without `~/.ssh/config` (known_hosts for `github.com` is still added).

#### Overridable variables

The following variables can be overridden at invocation time (see the `Justfile` for the full list):

| Variable                | Default                                                               | Description                                                                                                                                                          |
|-------------------------|-----------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `TZ`                    | `Europe/Amsterdam` (or `$TZ` from the environment)                    | Timezone baked into the image                                                                                                                                        |
| `PNPM_COREPACK_VERSION` | `$PNPM_COREPACK_VERSION` env; repo Actions variable in CI             | Pinned semver for `pnpm` (Corepack `prepare`)                                                                                                                        |
| `YARN_COREPACK_VERSION` | `$YARN_COREPACK_VERSION` env; repo Actions variable in CI             | Pinned semver for Yarn Berry (Corepack `prepare`)                                                                                                                    |
| `IMAGE_BASE`            | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base`       | Registry/repository path for the base image (`Dockerfile.base`)                                                                                                      |
| `IMAGE_TOOLING`         | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-tooling`    | Registry/repository path for the tooling child image (`Dockerfile.tooling`)                                                                                          |
| `IMAGE_PYTHON`          | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-python`     | Registry/repository path for the Python child image (`Dockerfile.python`)                                                                                            |
| `IMAGE_PLAYWRIGHT`      | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-playwright` | Registry/repository path for the Playwright child image (`Dockerfile.playwright`)                                                                                    |
| `VERSION`               | `local`                                                               | Primary image tag for **all four** images (also written into `IMAGE_VERSION` for the base image stamp)                                                               |
| `SUDO_PASSWORD_FILE`    | `config/.sudo-password`                                               | Optional one-line disposable password file; passed as secret `container_user_password` so it does **not** land in image history                                      |
| `SSH_CONFIG_FILE`       | `config/.ssh/config`                                                  | If this path exists and is non-empty, it is passed as secret `ssh_config`; otherwise the build skips SSH client config (mirrors unset/empty `SSH_CONFIG` in Actions) |

Example — override the timezone:

```bash
just TZ=UTC build
```

### Sudo password for ad-hoc package installs

The base Node image does not put `node` in the `sudo` group or set a login password. The image adds `node` to `sudo` and, if BuildKit secret `container_user_password` is provided (`just build` forwards `SUDO_PASSWORD_FILE` when that path exists), sets a disposable login password via `chpasswd`.

#### Setting the password

Use a **throwaway** one-line secret only. Prefer a gitignored file (default `config/.sudo-password`), not repeated command-line literals. The build strips CR/LF line endings from that file so Windows-style `CRLF` does not change the password versus what you type.

```bash
printf '%s\n' 'your-dev-only-secret' > config/.sudo-password
just build
```

#### Runtime caveat

**The running image must have been built with the secret.** A `prebuild` or `:latest` pull from GHCR only has a password if CI set the `CONTAINER_USER_PASSWORD` secret when that image was built; your local `config/.sudo-password` is not read at runtime. To confirm whether `node` has a password, run `docker exec -u root -it <container-name> passwd -S node` (`P` means a password is set; `NP` / locked means `sudo` auth will always fail until you rebuild with the secret or run `passwd node` as root).

If that file is absent, password-based `sudo` is unavailable until a root-capable step sets one, for example:

```bash
docker exec -u root -it coding-agent-sandbox-devcontainer passwd node
```

#### GitHub Actions

For **GitHub Actions** builds, optionally add a repository secret `CONTAINER_USER_PASSWORD` (same one-line throwaway value); the workflow writes it to a BuildKit secret so the image gets an interactive `sudo` password without a `--build-arg`. Leave the secret unset to skip (typical for CI).

### Watchtower (auto-updates from GHCR)

The compose stack includes Watchtower for labeled containers. Private GHCR images need a **Watchtower-only** Docker config (macOS `credsStore: osxkeychain` does not work inside the Watchtower container). See [.devcontainer/README.md](.devcontainer/README.md#ghcr-authentication-private-packages) for details.

```bash
just sync-watchtower-ghcr-auth   # once per machine / after token rotation
just watchtower-auth-check
just up
just update                      # one-shot pull + recreate now
```

| Recipe                      | Purpose                                                            |
|-----------------------------|--------------------------------------------------------------------|
| `sync-watchtower-ghcr-auth` | Write `config/.watchtower-docker/config.json` from `gh auth token` |
| `watchtower-auth-check`     | Fail fast if that file is missing                                  |
| `restart-watchtower`        | Reload auth after sync                                             |
| `update`                    | One-shot Watchtower with `--debug` (see `.devcontainer/README.md`) |
