# ──────────────────────────────────────────────────────────────────────────────
# Variables (shared across sections)
# ──────────────────────────────────────────────────────────────────────────────

# Running devcontainer container name. Used by Container lifecycle, Shell access,
# Claude sessions and Setup.
CONTAINER := "coding-agent-sandbox-devcontainer"

# Both compose files, in override-last order. Used by Container lifecycle and Watchtower.
COMPOSE_FILES := "-f .devcontainer/docker-compose.yml -f .devcontainer/docker-compose.override.yml"

# Five-layer image chain: base -> node -> tooling -> python -> agent.
# Each is published independently in CI. Used by both Registry (pull) and Image builds.
IMAGE_BASE := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base"
# Adds Node + all npm-global packages (JS dev tools + npm-based AI CLIs) on top of base.
IMAGE_NODE := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-node"
# Adds general (non-node) developer tooling (gh, glab, tofu, cloud CLIs, git-delta, just, just-lsp, chezmoi) on top of node.
IMAGE_TOOLING := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-tooling"
# Adds Python + uv and the Playwright browser stack (Chromium + system deps) on top of tooling.
IMAGE_PYTHON := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-python"
# Adds script-based AI agent installers + agent config (Claude Code, Tessl, herdr, apm) on top of python. This is the image the devcontainer runs.
IMAGE_AGENT := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-agent"

# ──────────────────────────────────────────────────────────────────────────────
# Default
# ──────────────────────────────────────────────────────────────────────────────

# --unsorted keeps recipes in source order, which is why the sections below run
# daily use first (lifecycle, access, sessions) and one-off or rare work last
# (setup, builds, registry, maintenance, watchtower).
# List all available recipes (default when running `just` with no arguments).
default:
    @just --list --unsorted

# ──────────────────────────────────────────────────────────────────────────────
# Container lifecycle
# ──────────────────────────────────────────────────────────────────────────────

# Start using docker compose by default.
[group('lifecycle')]
up: up-compose

# Restart using docker compose by default.
[group('lifecycle')]
restart: restart-compose

# Stop the devcontainer.
[group('lifecycle')]
stop:
    docker stop {{ CONTAINER }}

# Remove the devcontainer (stop and delete).
[group('lifecycle')]
rm:
    docker stop {{ CONTAINER }}
    docker rm {{ CONTAINER }}

# --- Backends behind up/restart ---

# Start the devcontainer with docker compose (what `up` calls).
[group('lifecycle')]
up-compose:
    docker compose {{ COMPOSE_FILES }} up -d

# Restart the devcontainer with docker compose (what `restart` calls).
[group('lifecycle')]
restart-compose:
    docker compose {{ COMPOSE_FILES }} restart

# Start the devcontainer with the devcontainer CLI instead of compose.
[group('lifecycle')]
up-dev:
    devcontainer up

# ──────────────────────────────────────────────────────────────────────────────
# Shell access
# ──────────────────────────────────────────────────────────────────────────────

# -u user: the container runs `user: root` so entrypoint.sh can seed the sudo
# password, but exec sessions must land as user (docker exec defaults to root).
# Enter the devcontainer with a shell (using docker exec).
[group('access')]
docker-enter:
    docker exec -it -u user {{ CONTAINER }} fish

# Step into a project directory and open a shell there (e.g. `just cd my-project`).
[group('access')]
cd PROJECT_NAME:
    docker exec -it -u user {{ CONTAINER }} fish -C "cd {{ PROJECT_NAME }}"

# Enter the devcontainer with a shell (using devcontainer CLI).
[group('access')]
devcontainer-enter:
    devcontainer exec fish

# ──────────────────────────────────────────────────────────────────────────────
# Claude sessions
# ──────────────────────────────────────────────────────────────────────────────

# -e TERM_PROGRAM lets the containerized Claude emit its own terminal notification,
# which cmux renders; the cmux Claude wrapper cannot reach into the container.
# See docs/guides/cmux-notifications.md.
# ARGS are forwarded to claude, which is what the resume recipes below use; the
# transcripts they resume from live in the claude-config volume, so they survive a stop.
# Step into a project directory and run Claude there (e.g. `just claude my-project`).
[group('sessions')]
claude PROJECT_NAME *ARGS:
    docker exec -it -u user -e TERM_PROGRAM {{ CONTAINER }} fish -C "cd {{ PROJECT_NAME }}; claude --dangerously-skip-permissions {{ ARGS }}"

# `claude agents` is Claude's own session index, so this needs no process scanning:
# it reports pid, cwd, sessionId, name and status. Add --json for the raw form.
# List the Claude sessions running in the container, with how to resume each.
[group('sessions')]
sessions:
    #!/usr/bin/env bash
    set -euo pipefail
    docker exec -u user {{ CONTAINER }} claude agents --json | jq -r '
        if length == 0 then "No Claude sessions running in {{ CONTAINER }}."
        else .[] | "\(.cwd | ltrimstr("/workspaces/")) (\(.name), \(.status)): just resume-session \(.sessionId)"
        end'

# Claude reports it itself if that project has no session yet.
# Continue a project's most recent session (e.g. `just resume my-project`).
[group('sessions')]
resume PROJECT_NAME:
    @just claude {{ PROJECT_NAME }} --continue

# Resuming by id ignores the cwd, so this lands in /workspaces (`cd .` from the
# container WORKDIR) and needs no project name.
# Resume one exact session by id, as printed by `just sessions`.
[group('sessions')]
resume-session SESSION_ID:
    @just claude . --resume {{ SESSION_ID }}

# ──────────────────────────────────────────────────────────────────────────────
# Setup (fresh machine, new project, after a rebuild)
# ──────────────────────────────────────────────────────────────────────────────

# Run once on a fresh machine before `just up`; the compose file declares them
# `external: true`, so they must exist before `devcontainer up` / `docker compose up`.
# Create the named volumes referenced by .devcontainer/docker-compose.yml (idempotent).
[group('setup')]
init-volumes:
    #!/usr/bin/env bash
    set -euo pipefail
    for v in claude-config gitlab-duo-config gitlab-cli-config aws-cli-config azure-cli-config oracle-cli-config opencode-config opencode-auth cursor-state vscode-state fish-history ssh-config gemini-config codex-config ccstatusline-config; do
        name="coding-agent-sandbox-$v"
        if ! docker volume inspect "$name" >/dev/null 2>&1; then
            docker volume create "$name"
        fi
    done

# Chown all named-volume mount targets back to user:user (fresh volumes are root-owned).
[group('setup')]
fix-volume-permissions:
    bash scripts/container/fix-volume-permissions.sh

# Runs extensions/install.sh from the coding-agent-config repo that config.sh clones at build.
# Skipped during the image build (the ~/.claude dir is a mounted volume); run once the container is up.
# Install agent extensions (Claude plugins/skills/MCP servers) in the running devcontainer.
[group('setup')]
install-extensions:
    docker exec -it -u user {{ CONTAINER }} bash -lc "cd ~/repositories/coding-agent-config && ./extensions/install.sh"

# PROJECT is the path under ~/Repositories (e.g. `agents/my-project`); the last
# segment becomes the /workspaces target. CONSISTENCY defaults to delegated.
# See docs/guides/mounting-projects.md.
# Append a project bind mount to the compose override, then restart to mount it.
[group('setup')]
add-project PROJECT CONSISTENCY="delegated":
    #!/usr/bin/env bash
    set -euo pipefail
    override=".devcontainer/docker-compose.override.yml"
    # Accept a bare `agents/foo`, `~/Repositories/agents/foo`, or an absolute
    # `/Users/x/Repositories/agents/foo`; keep only the part after Repositories/.
    project="{{ PROJECT }}"
    project="${project#*Repositories/}"
    line="      - \${HOME}/Repositories/${project}:/workspaces/$(basename "$project"):{{ CONSISTENCY }}"
    if grep -qF "$line" "$override"; then
        echo "already mounted: $project"
        exit 0
    fi
    printf '%s\n' "$line" >> "$override"
    echo "mounted: $project"
    # Applying the new mount recreates the container, which kills anything running
    # inside it (agents, shells). Only worth asking when it is actually up.
    if [[ -n "$(docker ps -q -f name="{{ CONTAINER }}")" ]]; then
        read -r -p "Restart the container to apply? Running agents/shells will be killed. [y/N] " ans
        if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
            echo "Not restarted. Run \`just up\` when ready."
            exit 0
        fi
    fi
    just up

# ──────────────────────────────────────────────────────────────────────────────
# Image builds
# ──────────────────────────────────────────────────────────────────────────────

# Tool and language versions are pinned in mise.toml (single source of truth).
# To bump: edit the version in mise.toml, then rebuild. See docs/guides/version-management.md.

TZ := env("TZ", "Europe/Amsterdam")
VERSION := "local"

# Build all five images (base -> node -> tooling -> python -> agent).
[group('build')]
build: build-base build-node build-tooling build-python build-agent

# --- One layer at a time, in chain order ---

# Tags :latest for the node stage FROM. No personal state baked in: git identity, ssh config
# and keys are injected at runtime via .devcontainer/docker-compose.override.yml bind mounts.
# Base devcontainer image (OS apt packages + shell/identity + mise, no Node, no developer tooling).
[group('build')]
build-base:
    docker build \
        --build-arg TZ="{{ TZ }}" \
        --build-arg IMAGE_VERSION="{{ VERSION }}-$(date +%Y%m%d%H%M%S)" \
        --tag "{{ IMAGE_BASE }}:{{ VERSION }}" \
        --tag "{{ IMAGE_BASE }}:latest" \
        --file Dockerfile.base \
        .

# Node layer on top of {{ IMAGE_BASE }}:latest (node/pnpm/yarn + all npm-global packages).
[group('build')]
build-node:
    docker build \
        --build-arg BASE_IMAGE="{{ IMAGE_BASE }}:latest" \
        --tag "{{ IMAGE_NODE }}:{{ VERSION }}" \
        --tag "{{ IMAGE_NODE }}:latest" \
        --file Dockerfile.node \
        .

# Tooling layer on top of {{ IMAGE_NODE }}:latest (general non-node dev tooling).
[group('build')]
build-tooling:
    docker build \
        --build-arg BASE_IMAGE="{{ IMAGE_NODE }}:latest" \
        --tag "{{ IMAGE_TOOLING }}:{{ VERSION }}" \
        --tag "{{ IMAGE_TOOLING }}:latest" \
        --file Dockerfile.tooling \
        .

# Python + Playwright layer on top of {{ IMAGE_TOOLING }}:latest (run after build-tooling or publish of :latest).
[group('build')]
build-python:
    docker build \
        --build-arg BASE_IMAGE="{{ IMAGE_TOOLING }}:latest" \
        --tag "{{ IMAGE_PYTHON }}:{{ VERSION }}" \
        --tag "{{ IMAGE_PYTHON }}:latest" \
        --file Dockerfile.python \
        .

# Agent layer on top of {{ IMAGE_PYTHON }}:latest (top of chain; the image the devcontainer runs).
[group('build')]
build-agent:
    docker build \
        --build-arg BASE_IMAGE="{{ IMAGE_PYTHON }}:latest" \
        --tag "{{ IMAGE_AGENT }}:{{ VERSION }}" \
        --tag "{{ IMAGE_AGENT }}:latest" \
        --file Dockerfile.agent \
        .

# ──────────────────────────────────────────────────────────────────────────────
# Registry
# ──────────────────────────────────────────────────────────────────────────────

# Pull all images from GitHub Container Registry with latest tag.
[group('registry')]
pull:
    docker pull {{ IMAGE_BASE }}:latest
    docker pull {{ IMAGE_NODE }}:latest
    docker pull {{ IMAGE_TOOLING }}:latest
    docker pull {{ IMAGE_PYTHON }}:latest
    docker pull {{ IMAGE_AGENT }}:latest

# ──────────────────────────────────────────────────────────────────────────────
# Docker maintenance
# ──────────────────────────────────────────────────────────────────────────────

# Show what Docker is using disk on (images, containers, volumes, build cache).
[group('maintenance')]
disk-usage:
    docker system df

# Safe: keeps named volumes and in-use images. Add `-a` yourself for a deeper clean.
# Remove stopped containers, unused networks, dangling images and build cache.
[group('maintenance')]
prune:
    docker system prune -f

# Remove dangling images (untagged <none> layers left behind by rebuilds).
[group('maintenance')]
prune-images:
    docker image prune -f

# Reclaim build cache only (leaves images/containers alone).
[group('maintenance')]
prune-build-cache:
    docker builder prune -f

# ──────────────────────────────────────────────────────────────────────────────
# Watchtower — auto-pull private GHCR images (compose service + just update)
# ──────────────────────────────────────────────────────────────────────────────

# --- Auth (inline config; not ~/.docker osxkeychain) ---
WATCHTOWER_DOCKER_CONFIG := "config/.watchtower-docker"
WATCHTOWER_DOCKER_CONFIG_FILE := WATCHTOWER_DOCKER_CONFIG + "/config.json"

# Sync config from $GHCR_TOKEN (or `gh`); once per machine / after token rotation. Pass --force to rewrite.
[group('watchtower')]
sync-watchtower-ghcr-auth *args:
    bash scripts/watchtower/sync-ghcr-auth.sh {{ args }}

# Fail if config missing (run sync-watchtower-ghcr-auth first).
[group('watchtower')]
watchtower-auth-check:
    #!/usr/bin/env bash
    set -euo pipefail
    f="{{ WATCHTOWER_DOCKER_CONFIG_FILE }}"
    if [[ ! -f "$f" ]]; then
        echo "error: missing $f — run: just sync-watchtower-ghcr-auth" >&2
        exit 1
    fi
    if ! grep -q '"ghcr.io"' "$f" || ! grep -q '"auth"' "$f"; then
        echo "error: $f has no ghcr.io auth — run: just sync-watchtower-ghcr-auth" >&2
        exit 1
    fi

# --- Run ---
# One-shot pull + recreate labeled containers (--debug: progress during pull).
[group('watchtower')]
update: watchtower-auth-check
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Watchtower: checking labeled containers (GHCR HEAD, then pull if digest changed)."
    echo "  Large images can take minutes; --debug logs pull start/end (no layer progress)."
    docker run --rm \
        -e DOCKER_API_VERSION=1.44 \
        -e DOCKER_CONFIG=/config \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$(pwd)/{{ WATCHTOWER_DOCKER_CONFIG }}:/config:ro" \
        ghcr.io/nicholas-fedor/watchtower:latest \
        --run-once --cleanup --label-enable --debug

# Reload compose Watchtower after sync.
[group('watchtower')]
restart-watchtower:
    docker compose {{ COMPOSE_FILES }} restart watchtower
