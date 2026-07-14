# Coding agent sandbox

A secure, containerized sandbox for running coding agents (Claude Code, Codex, Gemini, and others). It is a [Dev Container](https://containers.dev/) that runs agents against a pinned, reproducible toolchain isolated from the host rather than directly on your machine. The container runs as the non-root `node` user, and every tool and language version is pinned in [`mise.toml`](mise.toml).

## Quick start

Prerequisites: Docker (Docker Desktop or OrbStack) and [`just`](https://github.com/casey/just). Optionally VS Code or Cursor with the Dev Containers extension.

1. **Get the image.** Pull the prebuilt images from GHCR, or build them locally:

   ```bash
   just pull      # pull prebuilt images from GHCR
   # or
   just build     # build all five layers locally
   ```

2. **Start the container:**

   ```bash
   just up
   ```

3. **Install the agent extensions** (Claude plugins, skills, MCP servers) once the container is running:

   ```bash
   just install-extensions
   ```

4. **Get a shell inside**, then run an agent in one of your project directories:

   ```bash
   just docker-enter          # fish shell in the container
   just claude my-project     # cd into my-project and start Claude Code
   ```

Alternatively, open the repo in VS Code or Cursor and choose **Reopen in Container** to use it as an editor dev container.

## Everyday commands

Run `just` with no arguments to list every recipe. The common ones:

| Command                   | What it does                                                     |
|---------------------------|------------------------------------------------------------------|
| `just up`                 | Start the devcontainer (compose stack)                           |
| `just stop` / `just rm`   | Stop / remove the container                                      |
| `just docker-enter`       | Open a fish shell in the running container                       |
| `just cd my-project`      | Open a shell already `cd`'d into a project directory             |
| `just claude my-project`  | Start Claude Code inside a project directory                     |
| `just install-extensions` | Install Claude plugins/skills/MCP servers (run once, after `up`) |
| `just build`              | Build all five image layers locally                              |
| `just pull`               | Pull the prebuilt images from GHCR                               |
| `just update`             | One-shot Watchtower pull + recreate now                          |

## What's inside

The devcontainer is built from a layered stack of images (`base` → `node` → `tooling` → `python` → `agent`); the top `devcontainer-agent` image is the one that runs and ships the agent CLIs plus the developer tooling they shell out to.

- [Image layers](docs/tooling/images.md): what each of the five Dockerfiles adds.
- [apt packages](docs/tooling/apt-packages.md): the OS packages installed in the base and tooling layers.

### Configuration and scripts

| Path                       | Description                                                                                                                                                                                          |
|----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `.devcontainer/`           | VS Code / Cursor Dev Container configuration (optional; this repo often gitignores this tree locally).                                                                                               |
| `config/config.fish`       | Fish shell configuration (mise activation, Starship prompt, direnv hook, PATH).                                                                                                                      |
| `scripts/agents/config.sh` | Runs at build (`Dockerfile.agent`): clones the `coding-agent-config` repo and applies dotfiles via chezmoi. Extensions (plugins/skills/MCP) are installed at runtime with `just install-extensions`. |
| `scripts/agents/gemini.sh` | Gemini CLI extensions (CLI is installed in `Dockerfile.node`; this script is commented out in `Dockerfile.agent`).                                                                                   |
| `Justfile`                 | Convenience commands for building the images and common container tasks.                                                                                                                             |

## Documentation

How-to and reference guides for building, configuring, and running the sandbox.

| Doc                                                                | Covers                                                                                              |
|--------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| [building-images.md](docs/guides/building-images.md)               | Building the image layers: single-layer builds, `BASE_IMAGE`, CI, SSH config, overridable variables |
| [version-management.md](docs/guides/version-management.md)         | How languages and pinned tools are installed and versioned via mise                                 |
| [sudo-password.md](docs/guides/sudo-password.md)                   | Enabling `sudo` for ad-hoc package installs via a disposable password                               |
| [watchtower.md](docs/guides/watchtower.md)                         | Auto-updating containers from GHCR with Watchtower                                                  |
| [sharing-claude-history.md](docs/guides/sharing-claude-history.md) | Migrating Claude Code conversation history across machines or Docker volumes                        |
| [nvim.md](docs/guides/nvim.md)                                     | Minimal Neovim setup for editing in-container, with yank landing on the host clipboard              |

## Lessons learned (while building this project)

Investigation notes and writeups from building the sandbox: approaches that were tried, why they did or did not work, and what the current setup settled on.

| Doc                                                                               | Covers                                                                                           |
|-----------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| [brew-research.md](docs/lessons/brew-research.md)                                 | Whether Homebrew on Linux could replace the apt/mise package installs, and why it was rejected   |
| [fish-history-docker-mounts.md](docs/lessons/fish-history-docker-mounts.md)       | Why fish history breaks across Docker mount boundaries (cross-device `rename()`) and the fix     |
| [sharing-claude-config-lessons.md](docs/lessons/sharing-claude-config-lessons.md) | What went wrong bind-mounting the host `~/.claude` into the devcontainer, and what to do instead |
