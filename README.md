# Dev Container

This directory defines a [Dev Container](https://containers.dev/) environment for any coding agent project.

## Contents

| Path                 | Description                                                                                                                                          |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Dockerfile`         | Container image based on `node:20` (Debian Bookworm). Installs development tools, Claude Code CLI, Gemini CLI, Tessl CLI, GitHub CLI, and git-delta. |
| `devcontainer.json`  | VS Code / Cursor Dev Container configuration: build args, extension list, volume mounts, and post-start hooks.                                       |
| `config/config.fish` | Fish shell configuration (Starship prompt, direnv hook, PATH).                                                                                       |
| `scripts/claude.sh`  | Installs Claude Code plugins and MCP servers (Context7, Tessl, GitHub).                                                                              |
| `scripts/gemini.sh`  | Installs Gemini CLI extensions (requires authentication; disabled by default).                                                                       |
| `CLAUDE.md`          | Instructions for migrating Claude Code conversation history across machines or Docker volumes.                                                       |
| `Justfile`           | Convenience commands for working with the container image locally.                                                                                   |

## Justfile

Run commands from inside the `.devcontainer/` directory.

### Build the image

```bash
just build
```

Builds the Docker image and tags it as `coding-agent-sandbox-devcontainer`.

The following variables can be overridden at call time:

| Variable            | Default                                        | Description                                                            |
| ------------------- | ---------------------------------------------- | ---------------------------------------------------------------------- |
| `TZ`                | `Europe/Amsterdam` (or `$TZ` from environment) | Timezone baked into the image                                          |
| `GIT_DELTA_VERSION` | `0.18.2`                                       | Version of [git-delta](https://github.com/dandavison/delta) to install |
| `IMAGE`             | `coding-agent-sandbox-devcontainer`            | Image name and tag                                                     |

Example — override the timezone:

```bash
just TZ=UTC build
```
