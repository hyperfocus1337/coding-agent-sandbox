# Dev Container

This directory defines a [Dev Container](https://containers.dev/) environment for any coding agent project.

## Contents

| Path                             | Description                                                                                                                                                                                  |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Dockerfile`                     | Image based on [`node:26-trixie`](https://github.com/nodejs/docker-node/tree/main/26/trixie). Installs development tools, Claude Code CLI, Gemini CLI, Tessl CLI, GitHub CLI, and git-delta. |
| `.devcontainer/`                 | VS Code / Cursor Dev Container configuration (optional; this repo often gitignores this tree locally).                                                                                       |
| `config/config.fish`             | Fish shell configuration (Starship prompt, direnv hook, PATH).                                                                                                                               |
| `scripts/agents/claude.sh`       | Installs Claude Code plugins and MCP servers (Context7, Tessl, GitHub).                                                                                                                      |
| `scripts/agents/gemini.sh`       | Gemini CLI extensions (CLI is installed in the Dockerfile; this script is commented out there).                                                                                              |
| `docs/sharing-claude-history.md` | Notes for migrating Claude Code conversation history across machines or Docker volumes.                                                                                                      |
| `Justfile`                       | Convenience commands for building the image and common container tasks.                                                                                                                      |

## Justfile

Run `just` from the **repository root** (where `Dockerfile` and `Justfile` live).

### Build the image

```bash
just build
```

Produces two tags using the Just variables `IMAGE` and `VERSION`: for example `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer:local` and `…:latest` with the defaults in the table below. The Dockerfile does **not** embed Corepack semver defaults; `just build` and CI pass them. SSH client config uses the optional BuildKit secret `ssh_config` (same mechanism locally and in GitHub Actions: repo secret `SSH_CONFIG` → `secret-files`). If the secret is missing or empty, the image is built without `~/.ssh/config` (known_hosts for `github.com` is still added).

The following variables can be overridden at invocation time (see the `Justfile` for the full list):

| Variable                | Default                                                    | Description                                                                                                                                                          |
| ----------------------- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TZ`                    | `Europe/Amsterdam` (or `$TZ` from the environment)         | Timezone baked into the image                                                                                                                                        |
| `GIT_DELTA_VERSION`     | `0.18.2`                                                   | Version of [git-delta](https://github.com/dandavison/delta) to install                                                                                               |
| `PNPM_COREPACK_VERSION` | `11.0.9`                                                   | Pinned semver for `pnpm` (Corepack `prepare`)                                                                                                                        |
| `YARN_COREPACK_VERSION` | `4.14.1`                                                   | Pinned semver for Yarn Berry (Corepack `prepare`)                                                                                                                    |
| `IMAGE`                 | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer` | Registry/repository path for `docker build` tags                                                                                                                     |
| `VERSION`               | `local`                                                    | Primary image tag (also written into `IMAGE_VERSION` for the image stamp)                                                                                            |
| `SUDO_PASSWORD_FILE`    | `config/.sudo-password`                                    | Optional one-line disposable password file; passed as secret `container_user_password` so it does **not** land in image history                                      |
| `SSH_CONFIG_FILE`       | `config/.ssh/config`                                       | If this path exists and is non-empty, it is passed as secret `ssh_config`; otherwise the build skips SSH client config (mirrors unset/empty `SSH_CONFIG` in Actions) |

Example — override the timezone:

```bash
just TZ=UTC build
```

### Sudo password for ad-hoc package installs

The base Node image does not put `node` in the `sudo` group or set a login password. The image adds `node` to `sudo` and, if BuildKit secret `container_user_password` is provided (`just build` forwards `SUDO_PASSWORD_FILE` when that path exists), sets a disposable login password via `chpasswd`.

Use a **throwaway** one-line secret only. Prefer a gitignored file (default `config/.sudo-password`), not repeated command-line literals.

```bash
printf '%s\n' 'your-dev-only-secret' > config/.sudo-password
just build
```

If that file is absent, password-based `sudo` is unavailable until a root-capable step sets one, for example:

```bash
docker exec -u root -it coding-agent-sandbox-devcontainer passwd node
```

For **GitHub Actions** builds, optionally add a repository secret `CONTAINER_USER_PASSWORD` (same one-line throwaway value); the workflow writes it to a BuildKit secret so the image gets an interactive `sudo` password without a `--build-arg`. Leave the secret unset to skip (typical for CI).
