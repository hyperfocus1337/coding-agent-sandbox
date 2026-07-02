# Dev Container

This directory defines a [Dev Container](https://containers.dev/) environment for any coding agent project.

## Contents

### Images

| Path                    | Description                                                                                                                                                                                                                                                                                                                                                                                                                             |
|-------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Dockerfile.base`       | Base image on [`debian:trixie-slim`](https://hub.docker.com/_/debian) (Debian 13 stable). A lean shell/OS baseline only (fish, git, curl, gnupg, openssh-client, neovim, direnv, …; see [apt packages](#apt-packages)), then [mise](https://github.com/jdx/mise) installs yq and Starship. SSH + sudo bootstrap, default editor, permissions — **no Node, no developer tooling, no Python**. Consume this for a minimal shell baseline. |
| `Dockerfile.node`       | Child image on top of `devcontainer-base`: Node + pnpm/yarn via mise, then **all** npm-global packages — JS dev tools (Prettier, markdownlint-cli2, ESLint, neonctl) and the npm-based AI CLIs (Anthropic sandbox-runtime, Codex, Gemini, OpenCode, GitLab Duo). `BASE_IMAGE` selects the base (default `…/devcontainer-base:latest`; CI pins digest after push).                                                                       |
| `Dockerfile.tooling`    | Child image on top of `devcontainer-node`: the AI-agent CLI toolkit (ripgrep, fd, bat, …) plus general (non-node) developer tooling — GitHub CLI, GitLab CLI, OpenTofu, Azure/AWS CLIs, git-delta, `just`, just-lsp, chezmoi. `BASE_IMAGE` selects the base (default `…/devcontainer-node:latest`; CI pins digest after push).                                                                                                          |
| `Dockerfile.python`     | Child image on top of `devcontainer-tooling`: adds Python + `uv` via mise. `BASE_IMAGE` selects the base (default `…/devcontainer-tooling:latest`; CI pins digest after push).                                                                                                                                                                                                                                                          |
| `Dockerfile.playwright` | Child image on top of `devcontainer-python`: Playwright system deps and Chromium (`PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`). `BASE_IMAGE` selects the base (default `…/devcontainer-python:latest`; CI pins digest after push).                                                                                                                                                                                                        |
| `Dockerfile.agent`      | Top image on top of `devcontainer-playwright`: script/curl-based AI agent installers (Claude Code, Tessl, herdr, apm), sandbox-runtime system deps, and agent config (Claude plugins/MCP via `scripts/agents/config.sh`). **This is the image the devcontainer runs.** `BASE_IMAGE` selects the base (default `…/devcontainer-playwright:latest`; CI pins digest after push).                                                           |

### apt packages

OS packages split across two layers: `Dockerfile.base` keeps a lean shell/OS baseline, and `Dockerfile.tooling` adds the AI-agent CLI toolkit and other developer utilities. The final `devcontainer-agent` image contains both.

**Baseline** (`Dockerfile.base`) — only what the base's own build steps and the shell need:

| Package            | Provides    | Purpose                                           |
|--------------------|-------------|---------------------------------------------------|
| `less`             |             | pager                                             |
| `git`              |             | version control                                   |
| `procps`           | `ps`, `top` | process inspection                                |
| `sudo`             |             | privilege escalation (see sudo password section)  |
| `fzf`              |             | fuzzy finder                                      |
| `fish`             |             | default interactive shell                         |
| `unzip`            |             | archive extraction                                |
| `ca-certificates`  |             | TLS root certs                                    |
| `curl`             |             | HTTP download (mise/extrepo, vendor installers)   |
| `gnupg` / `gnupg2` | `gpg`       | signature/key handling for apt keyrings           |
| `neovim`           | `nvim`      | default editor (`EDITOR`/`VISUAL`)                |
| `direnv`           |             | per-directory env loading                         |
| `openssh-client`   | `ssh`       | `ssh-keyscan` for the SSH bootstrap; git over SSH |

`yq` and `starship` are also installed in the base image, via mise (not apt).

**Developer + AI-agent tooling** (`Dockerfile.tooling`) — utilities coding agents shell out to plus general dev/network/data tools, moved off the baseline so the base layer stays minimal:

| Package             | Provides                        | Purpose                                           |
|---------------------|---------------------------------|---------------------------------------------------|
| `ripgrep`           | `rg`                            | fast recursive grep; Claude Code's search backend |
| `fd-find`           | `fd` (symlinked from `fdfind`)  | fast file finder                                  |
| `bat`               | `bat` (symlinked from `batcat`) | `cat` with syntax highlight + line numbers        |
| `shellcheck`        |                                 | shell script linter                               |
| `yamllint`          |                                 | YAML linter                                       |
| `universal-ctags`   | `ctags`                         | symbol/tag indexing for code nav                  |
| `patch`             |                                 | apply unified diffs                               |
| `patchutils`        | `filterdiff`, `interdiff`, …    | manipulate patches                                |
| `miller`            | `mlr`                           | CSV/TSV/JSON stream processor                     |
| `csvkit`            | `csvlook`, `csvcut`, …          | CSV toolkit                                       |
| `httpie`            | `http`, `https`                 | friendly HTTP client                              |
| `netcat-openbsd`    | `nc`                            | TCP/UDP socket tool                               |
| `socat`             |                                 | bidirectional socket relay                        |
| `lsof`              |                                 | list open files / ports                           |
| `file`              |                                 | detect file type by content                       |
| `moreutils`         | `sponge`, `ts`, `chronic`, …    | extra Unix utilities                              |
| `ncdu`              |                                 | interactive disk usage browser                    |
| `strace`            |                                 | trace syscalls / signals                          |
| `rsync`             |                                 | fast incremental file sync                        |
| `wget`              |                                 | HTTP download (gh keyring fetch)                  |
| `dnsutils`          | `dig`, `nslookup`               | DNS debugging                                     |
| `jq`                |                                 | JSON processor                                    |
| `tree`              |                                 | directory tree view                               |
| `man-db`            | `man`                           | manual pages                                      |
| `postgresql-client` | `psql`                          | Postgres CLI                                      |

### Configuration and scripts

| Path                       | Description                                                                                                                                                                                          |
|----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `.devcontainer/`           | VS Code / Cursor Dev Container configuration (optional; this repo often gitignores this tree locally).                                                                                               |
| `config/config.fish`       | Fish shell configuration (mise activation, Starship prompt, direnv hook, PATH).                                                                                                                      |
| `scripts/agents/config.sh` | Runs at build (`Dockerfile.agent`): clones the `coding-agent-config` repo and applies dotfiles via chezmoi. Extensions (plugins/skills/MCP) are installed at runtime with `just install-extensions`. |
| `scripts/agents/gemini.sh` | Gemini CLI extensions (CLI is installed in `Dockerfile.node`; this script is commented out in `Dockerfile.agent`).                                                                                   |
| `Justfile`                 | Convenience commands for building the images and common container tasks.                                                                                                                             |

### Docs and version pinning

| Path                             | Description                                                                                                 |
|----------------------------------|-------------------------------------------------------------------------------------------------------------|
| `docs/sharing-claude-history.md` | Notes for migrating Claude Code conversation history across machines or Docker volumes.                     |
| `docs/version-management.md`     | How languages and pinned tools are installed and versioned via mise (all versions live in `mise.toml`).     |
| `mise.toml`                      | Single source of truth for every tool/language version; COPY'd into the base image as mise's global config. |

## Justfile

Run `just` from the **repository root** (where `Dockerfile.base` and `Justfile` live).

### Build the images

```bash
just build
```

This runs **`build-base`** → **`build-node`** → **`build-tooling`** → **`build-python`** → **`build-playwright`** → **`build-agent`**, producing six images tagged with `VERSION` (default `local`) and `latest`:

- `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base:{VERSION,latest}`
- `…/devcontainer-node:{VERSION,latest}`
- `…/devcontainer-tooling:{VERSION,latest}`
- `…/devcontainer-python:{VERSION,latest}`
- `…/devcontainer-playwright:{VERSION,latest}`
- `…/devcontainer-agent:{VERSION,latest}`

#### Building a single layer

Use **`just build-base`**, **`just build-node`**, **`just build-tooling`**, **`just build-python`**, **`just build-playwright`**, or **`just build-agent`** alone when you only need one layer (for example, after pulling a published parent from GHCR).

#### Selecting the base image

`Dockerfile.node`, `Dockerfile.tooling`, `Dockerfile.python`, `Dockerfile.playwright`, and `Dockerfile.agent` accept **`BASE_IMAGE`** (must match the layer you extend). The recipes wire each child to the prior layer's `:latest` tag locally so overrides to `IMAGE_BASE`/`IMAGE_NODE`/`IMAGE_TOOLING`/`IMAGE_PYTHON`/`IMAGE_PLAYWRIGHT` still stack.

#### Tool and language versions

Languages (Node, Python), package managers (pnpm, yarn, uv), and the pinned
release binaries (git-delta, glab, just, just-lsp, terraform, yq, starship) are
all installed and version-pinned via [mise](https://github.com/jdx/mise). Every
version lives in one file, [`mise.toml`](mise.toml) at the repo root, which is
COPY'd into the base image as mise's global config; each layer installs its
subset with `mise install`. To bump a version, edit `mise.toml` and rebuild. See
[docs/version-management.md](docs/version-management.md) for the per-layer
breakdown, backends, and adding tools.

#### GitHub Actions builds

In **GitHub Actions** (`.github/workflows/docker-devcontainer.yml`), six independent jobs (`build-base`, `build-node`, `build-tooling`, `build-python`, `build-playwright`, `build-agent`) each build and push their own image to GHCR with metadata-driven tags (branch, PR, semver, SHA, `latest` on the default branch). Each job is a separate runner — `devcontainer-base` is pushed and pullable the moment its job finishes, regardless of whether the downstream `node`/`tooling`/`python`/`playwright`/`agent` jobs are still running or have failed. Downstream jobs pin **`BASE_IMAGE`** to the upstream **digest** so child images match exactly. On **pull requests** images are not pushed, so the downstream jobs fall back to the parent's `:latest` tag on GHCR for Dockerfile validation.

Tool and language versions are not build-args — they are pinned in `mise.toml` and installed per layer with `mise install` (see [docs/version-management.md](docs/version-management.md)).

#### SSH client config

SSH client config uses the optional BuildKit secret `ssh_config` (same mechanism locally and in GitHub Actions: repo secret `SSH_CONFIG` → `secret-files`). If the secret is missing or empty, the image is built without `~/.ssh/config` (known_hosts for `github.com` is still added).

#### Overridable variables

The following variables can be overridden at invocation time (see the `Justfile` for the full list):

| Variable             | Default                                                               | Description                                                                                                                                                          |
|----------------------|-----------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `TZ`                 | `Europe/Amsterdam` (or `$TZ` from the environment)                    | Timezone baked into the image                                                                                                                                        |
| `IMAGE_BASE`         | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base`       | Registry/repository path for the base image (`Dockerfile.base`)                                                                                                      |
| `IMAGE_NODE`         | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-node`       | Registry/repository path for the Node child image (`Dockerfile.node`)                                                                                                |
| `IMAGE_TOOLING`      | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-tooling`    | Registry/repository path for the tooling child image (`Dockerfile.tooling`)                                                                                          |
| `IMAGE_PYTHON`       | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-python`     | Registry/repository path for the Python child image (`Dockerfile.python`)                                                                                            |
| `IMAGE_PLAYWRIGHT`   | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-playwright` | Registry/repository path for the Playwright child image (`Dockerfile.playwright`)                                                                                    |
| `IMAGE_AGENT`        | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-agent`      | Registry/repository path for the agent top image (`Dockerfile.agent`)                                                                                                |
| `VERSION`            | `local`                                                               | Primary image tag for **all six** images (also written into `IMAGE_VERSION` for the base image stamp)                                                                |
| `SUDO_PASSWORD_FILE` | `config/.sudo-password`                                               | Optional one-line disposable password file; passed as secret `container_user_password` so it does **not** land in image history                                      |
| `SSH_CONFIG_FILE`    | `config/.ssh/config`                                                  | If this path exists and is non-empty, it is passed as secret `ssh_config`; otherwise the build skips SSH client config (mirrors unset/empty `SSH_CONFIG` in Actions) |

Example — override the timezone:

```bash
just TZ=UTC build
```

### Agent extensions

`scripts/agents/config.sh` runs during the build (`Dockerfile.agent`) and applies dotfiles via chezmoi from the `coding-agent-config` repo it clones to `~/repositories/coding-agent-config`. Installing the Claude Code extensions (plugins, skills, MCP servers) is deferred to runtime, because `~/.claude` is a mounted volume that is empty until the container is up. Run it once the container is running:

```bash
just install-extensions
```

This execs `extensions/install.sh` from that cloned repo inside the running container.

### Sudo password for ad-hoc package installs

The base image does not put `node` in the `sudo` group or set a login password. The image adds `node` to `sudo` and, if BuildKit secret `container_user_password` is provided (`just build` forwards `SUDO_PASSWORD_FILE` when that path exists), sets a disposable login password via `chpasswd`.

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
