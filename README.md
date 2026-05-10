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

Produces two tags using the Just variables `IMAGE` and `VERSION`: for example `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer:local` and `…:latest` with the defaults in the table below. The build also requires `config/.ssh/config` for BuildKit secret `ssh_config` (see `Dockerfile`).

The following variables can be overridden at invocation time (see the `Justfile` for the full list):

| Variable                  | Default                                                    | Description                                                                                                            |
| ------------------------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `TZ`                      | `Europe/Amsterdam` (or `$TZ` from the environment)         | Timezone baked into the image                                                                                          |
| `GIT_DELTA_VERSION`       | `0.18.2`                                                   | Version of [git-delta](https://github.com/dandavison/delta) to install                                                 |
| `IMAGE`                   | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer` | Registry/repository path for `docker build` tags                                                                       |
| `VERSION`                 | `local`                                                    | Primary image tag (also written into `IMAGE_VERSION` for the image stamp)                                              |
| `CONTAINER_USER_PASSWORD` | _empty_                                                    | If set, configures the dev user’s **Unix** password and enables `sudo apt install …` inside the container (see below). |
| `SSH_CONFIG_FILE`         | `config/.ssh/config`                                       | Host path passed to `docker build --secret id=ssh_config,src=…`                                                        |

Example — override the timezone:

```bash
just TZ=UTC build
```

### Sudo password for ad-hoc package installs

The base Node image does not put `node` in the `sudo` group or set a login password. When you set `CONTAINER_USER_PASSWORD`, the image grants `sudo` and runs `chpasswd` so you can run `sudo apt install …` interactively.

Use a **throwaway** password only: build args can show up in **`docker image history`**. Do not use a password you reuse elsewhere, and avoid setting this in CI unless you accept that risk.

```bash
CONTAINER_USER_PASSWORD='your-dev-only-secret' just build
```

If you build **without** `CONTAINER_USER_PASSWORD`, password-based `sudo` is unavailable until a root-capable step sets one, for example:

```bash
docker exec -u root -it coding-agent-sandbox-devcontainer passwd node
```
