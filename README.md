# Dev Container

This directory defines a [Dev Container](https://containers.dev/) environment
for any coding agent project.

## Contents

| Path                             | Description                                                                                                                                                                                                                                                                                                           |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Dockerfile.base`                | Base image on [`node:26-trixie`](https://github.com/nodejs/docker-node/tree/main/26/trixie). OS apt packages, Emacs, Starship, Corepack (pnpm/yarn), SSH + sudo bootstrap, default editor, permissions — **no developer tooling, no Python**. Consume this for a minimal Node + shell baseline.                       |
| `Dockerfile.tooling`             | Child image on top of `devcontainer-base`: general developer tooling (GitHub CLI, git-delta, just-lsp) then AI tooling (Anthropic sandbox-runtime, Claude Code, Codex, Gemini, OpenCode, Tessl, Claude plugins/MCP). `BASE_IMAGE` selects the base (default `…/devcontainer-base:latest`; CI pins digest after push). |
| `Dockerfile.python`              | Child image on top of `devcontainer-tooling`: adds `python3` + `uv` + `rust-just`. `BASE_IMAGE` selects the base (default `…/devcontainer-tooling:latest`; CI pins digest after push).                                                                                                                                |
| `Dockerfile.playwright`          | Child image on top of `devcontainer-python`: Playwright system deps and Chromium (`PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`). `BASE_IMAGE` selects the base (default `…/devcontainer-python:latest`; CI pins digest after push).                                                                                      |
| `.devcontainer/`                 | VS Code / Cursor Dev Container configuration (optional; this repo often gitignores this tree locally).                                                                                                                                                                                                                |
| `config/config.fish`             | Fish shell configuration (Starship prompt, direnv hook, PATH).                                                                                                                                                                                                                                                        |
| `scripts/agents/claude.sh`       | Installs Claude Code plugins and MCP servers (Context7, Tessl, GitHub).                                                                                                                                                                                                                                               |
| `scripts/agents/gemini.sh`       | Gemini CLI extensions (CLI is installed in `Dockerfile.tooling`; this script is commented out there).                                                                                                                                                                                                                 |
| `docs/sharing-claude-history.md` | Notes for migrating Claude Code conversation history across machines or Docker volumes.                                                                                                                                                                                                                               |
| `Justfile`                       | Convenience commands for building the images and common container tasks.                                                                                                                                                                                                                                              |

## Justfile

Run `just` from the **repository root** (where `Dockerfile.base` and `Justfile`
live).

### Build the images

```bash
just build
```

This runs **`build-base`** → **`build-tooling`** → **`build-python`** →
**`build-playwright`**, producing four images tagged with `VERSION` (default
`local`) and `latest`:

- `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base:{VERSION,latest}`
- `…/devcontainer-tooling:{VERSION,latest}`
- `…/devcontainer-python:{VERSION,latest}`
- `…/devcontainer-playwright:{VERSION,latest}`

Use **`just build-base`**, **`just build-tooling`**, **`just build-python`**, or
**`just build-playwright`** alone when you only need one layer (for example,
after pulling a published parent from GHCR).

`Dockerfile.tooling`, `Dockerfile.python`, and `Dockerfile.playwright` accept
**`BASE_IMAGE`** (must match the layer you extend). The recipes wire each child
to the prior layer's `:latest` tag locally so overrides to
`IMAGE_BASE`/`IMAGE_TOOLING`/`IMAGE_PYTHON` still stack.

`Dockerfile.base` does **not** embed Corepack semver defaults; `just build` and
CI pass them via build args. `GIT_DELTA_VERSION` and `JUST_LSP_VERSION` are
consumed by `Dockerfile.tooling`.

In **GitHub Actions** (`.github/workflows/docker-devcontainer.yml`), four
independent jobs (`build-base`, `build-tooling`, `build-python`,
`build-playwright`) each build and push their own image to GHCR with
metadata-driven tags (branch, PR, semver, SHA, `latest` on the default branch).
Each job is a separate runner — `devcontainer-base` is pushed and pullable the
moment its job finishes, regardless of whether the downstream
`tooling`/`python`/`playwright` jobs are still running or have failed.
Downstream jobs pin **`BASE_IMAGE`** to the upstream **digest** so child images
match exactly. On **pull requests** images are not pushed, so the downstream
jobs fall back to the parent's `:latest` tag on GHCR for Dockerfile validation.

Repository **variables** supply `GIT_DELTA_VERSION`, `PNPM_COREPACK_VERSION`,
`YARN_COREPACK_VERSION`, and `JUST_LSP_VERSION` (**Settings → Secrets and
variables → Actions → Variables**); keep those aligned with the Justfile
defaults when you bump pins.

SSH client config uses the optional BuildKit secret `ssh_config` (same mechanism
locally and in GitHub Actions: repo secret `SSH_CONFIG` → `secret-files`). If
the secret is missing or empty, the image is built without `~/.ssh/config`
(known_hosts for `github.com` is still added).

The following variables can be overridden at invocation time (see the `Justfile`
for the full list):

| Variable                | Default                                                               | Description                                                                                                                                                          |
| ----------------------- | --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TZ`                    | `Europe/Amsterdam` (or `$TZ` from the environment)                    | Timezone baked into the image                                                                                                                                        |
| `GIT_DELTA_VERSION`     | `0.18.2`                                                              | Version of [git-delta](https://github.com/dandavison/delta) to install                                                                                               |
| `PNPM_COREPACK_VERSION` | `11.0.9`                                                              | Pinned semver for `pnpm` (Corepack `prepare`)                                                                                                                        |
| `YARN_COREPACK_VERSION` | `4.14.1`                                                              | Pinned semver for Yarn Berry (Corepack `prepare`)                                                                                                                    |
| `JUST_LSP_VERSION`      | `0.3.4`                                                               | [just-lsp](https://github.com/terror/just-lsp) release tag; set matching **Actions variable** for CI builds                                                          |
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

The base Node image does not put `node` in the `sudo` group or set a login
password. The image adds `node` to `sudo` and, if BuildKit secret
`container_user_password` is provided (`just build` forwards
`SUDO_PASSWORD_FILE` when that path exists), sets a disposable login password
via `chpasswd`.

Use a **throwaway** one-line secret only. Prefer a gitignored file (default
`config/.sudo-password`), not repeated command-line literals. The build strips
CR/LF line endings from that file so Windows-style `CRLF` does not change the
password versus what you type.

**The running image must have been built with the secret.** A `prebuild` or
`:latest` pull from GHCR only has a password if CI set the
`CONTAINER_USER_PASSWORD` secret when that image was built; your local
`config/.sudo-password` is not read at runtime. To confirm whether `node` has a
password, run `docker exec -u root -it <container-name> passwd -S node` (`P`
means a password is set; `NP` / locked means `sudo` auth will always fail until
you rebuild with the secret or run `passwd node` as root).

```bash
printf '%s\n' 'your-dev-only-secret' > config/.sudo-password
just build
```

If that file is absent, password-based `sudo` is unavailable until a
root-capable step sets one, for example:

```bash
docker exec -u root -it coding-agent-sandbox-devcontainer passwd node
```

For **GitHub Actions** builds, optionally add a repository secret
`CONTAINER_USER_PASSWORD` (same one-line throwaway value); the workflow writes
it to a BuildKit secret so the image gets an interactive `sudo` password without
a `--build-arg`. Leave the secret unset to skip (typical for CI).
