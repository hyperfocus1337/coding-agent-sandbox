# ──────────────────────────────────────────────────────────────────────────────
# Variables (shared across sections)
# ──────────────────────────────────────────────────────────────────────────────

# Running devcontainer container name. Used by both Container lifecycle and Shell access.
CONTAINER := "coding-agent-sandbox-devcontainer"

# Four-layer image chain: base -> tooling -> python -> playwright. Each is published independently in CI.
# Used by both Registry (pull) and Image builds.
IMAGE_BASE := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base"
# Adds developer + AI tooling (git-delta, just-lsp, sandbox-runtime, Claude/Codex/Gemini/OpenCode/Tessl) on top of base.
IMAGE_TOOLING := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-tooling"
# Adds Python + uv on top of tooling.
IMAGE_PYTHON := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-python"
# Adds Playwright (Chromium + system deps) on top of python.
IMAGE_PLAYWRIGHT := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-playwright"

# ──────────────────────────────────────────────────────────────────────────────
# Default
# ──────────────────────────────────────────────────────────────────────────────

# List all available recipes (default when running `just` with no arguments).
default:
    @just --list

# ──────────────────────────────────────────────────────────────────────────────
# Shell access
# ──────────────────────────────────────────────────────────────────────────────

# Enter the devcontainer with a shell (using devcontainer CLI).
enter:
    devcontainer exec fish

# Enter the devcontainer with a shell (using docker exec).
docker-enter:
    docker exec -it {{ CONTAINER }} fish

# Step into a project directory and open a shell there (e.g. `just cd my-project`).
cd PROJECT_NAME:
    docker exec -it {{ CONTAINER }} fish -C "cd {{ PROJECT_NAME }}"

# Step into a project directory and run Claude there (e.g. `just claude my-project`).
claude PROJECT_NAME:
    docker exec -it {{ CONTAINER }} fish -C "cd {{ PROJECT_NAME }}; claude --dangerously-skip-permissions"

# ──────────────────────────────────────────────────────────────────────────────
# Registry
# ──────────────────────────────────────────────────────────────────────────────

# Pull all images from GitHub Container Registry with latest tag.
pull:
    docker pull {{ IMAGE_BASE }}:latest
    docker pull {{ IMAGE_TOOLING }}:latest
    docker pull {{ IMAGE_PYTHON }}:latest
    docker pull {{ IMAGE_PLAYWRIGHT }}:latest

# ──────────────────────────────────────────────────────────────────────────────
# Versions
# ──────────────────────────────────────────────────────────────────────────────

# Resolve the latest upstream versions of the binary tools and rewrite versions.lock.
# Manual maintenance step; review the diff and commit. Requires curl + jq.
lock:
    bash scripts/versions/resolve.sh

# ──────────────────────────────────────────────────────────────────────────────
# Image builds
# ──────────────────────────────────────────────────────────────────────────────

TZ := env("TZ", "Europe/Amsterdam")
PNPM_COREPACK_VERSION := env("PNPM_COREPACK_VERSION", "11.0.9")
YARN_COREPACK_VERSION := env("YARN_COREPACK_VERSION", "4.14.1")
VERSION := "local"
SSH_CONFIG_FILE := "config/.ssh/config"

# Optional: one-line file with a disposable Unix password for `$USERNAME` (BuildKit secret
# `container_user_password`; not stored in image history like a `--build-arg`). Omit for CI.
SUDO_PASSWORD_FILE := "config/.sudo-password"

# Base devcontainer image (Node + OS apt packages + shell/identity, no developer tooling).
# Tags :latest for the tooling stage FROM.
build-base:
    #!/usr/bin/env bash
    set -euo pipefail
    SECRET_ARGS=()
    # Check if the SSH config file exists (-f) and is not empty (-s)
    if [[ -f "{{ SSH_CONFIG_FILE }}" ]] && [[ -s "{{ SSH_CONFIG_FILE }}" ]]; then
        SECRET_ARGS+=(--secret id=ssh_config,src="{{ SSH_CONFIG_FILE }}")
    fi
    # Check if the sudo password file exists (-f) and is not empty (-s)
    if [[ -f "{{ SUDO_PASSWORD_FILE }}" ]] && [[ -s "{{ SUDO_PASSWORD_FILE }}" ]]; then
        SECRET_ARGS+=(--secret id=container_user_password,src="{{ SUDO_PASSWORD_FILE }}")
    fi
    docker build \
        "${SECRET_ARGS[@]}" \
        --build-arg TZ="{{ TZ }}" \
        --build-arg PNPM_COREPACK_VERSION="{{ PNPM_COREPACK_VERSION }}" \
        --build-arg YARN_COREPACK_VERSION="{{ YARN_COREPACK_VERSION }}" \
        --build-arg IMAGE_VERSION="{{ VERSION }}-$(date +%Y%m%d%H%M%S)" \
        --tag "{{ IMAGE_BASE }}:{{ VERSION }}" \
        --tag "{{ IMAGE_BASE }}:latest" \
        --file Dockerfile.base \
        .

# Tooling layer on top of {{ IMAGE_BASE }}:latest (general dev tooling + AI tooling).
build-tooling:
    docker build \
        --build-arg BASE_IMAGE="{{ IMAGE_BASE }}:latest" \
        --tag "{{ IMAGE_TOOLING }}:{{ VERSION }}" \
        --tag "{{ IMAGE_TOOLING }}:latest" \
        --file Dockerfile.tooling \
        .

# Python layer on top of {{ IMAGE_TOOLING }}:latest (run after build-tooling or publish of :latest).
build-python:
    docker build \
        --build-arg BASE_IMAGE="{{ IMAGE_TOOLING }}:latest" \
        --tag "{{ IMAGE_PYTHON }}:{{ VERSION }}" \
        --tag "{{ IMAGE_PYTHON }}:latest" \
        --file Dockerfile.python \
        .

# Playwright layer on top of {{ IMAGE_PYTHON }}:latest (run after build-python or publish of :latest).
build-playwright:
    docker build \
        --build-arg BASE_IMAGE="{{ IMAGE_PYTHON }}:latest" \
        --tag "{{ IMAGE_PLAYWRIGHT }}:{{ VERSION }}" \
        --tag "{{ IMAGE_PLAYWRIGHT }}:latest" \
        --file Dockerfile.playwright \
        .

# Build all four images (base -> tooling -> python -> playwright).
build: build-base build-tooling build-python build-playwright

# ──────────────────────────────────────────────────────────────────────────────
# Container lifecycle
# ──────────────────────────────────────────────────────────────────────────────

COMPOSE_FILES := "-f .devcontainer/docker-compose.yml -f .devcontainer/docker-compose.override.yml"

# Create the named volumes referenced by .devcontainer/docker-compose.yml (idempotent).
# Run once on a fresh machine before `just up`; the compose file declares them
# `external: true`, so they must exist before `devcontainer up` / `docker compose up`.
init-volumes:
    #!/usr/bin/env bash
    set -euo pipefail
    for v in claude-config gitlab-duo-config gitlab-cli-config aws-cli-config azure-cli-config oracle-cli-config opencode-config opencode-auth cursor-state vscode-state fish-history ssh-config; do
        name="coding-agent-sandbox-$v"
        if ! docker volume inspect "$name" >/dev/null 2>&1; then
            docker volume create "$name"
        fi
    done

# Start using docker compose by default.
up: up-compose

# Restart using docker compose by default.
restart: restart-compose

# Start the devcontainer.
up-dev:
    devcontainer up

# Start the devcontainer.
up-compose:
    docker compose {{ COMPOSE_FILES }} up -d

# Restart the devcontainer.
restart-compose:
    docker compose {{ COMPOSE_FILES }} restart

# Stop the devcontainer.
stop:
    docker stop {{ CONTAINER }}

# Remove the devcontainer (stop and delete).
rm:
    docker stop {{ CONTAINER }}
    docker rm {{ CONTAINER }}

# ──────────────────────────────────────────────────────────────────────────────
# Watchtower — auto-pull private GHCR images (compose service + just update)
# ──────────────────────────────────────────────────────────────────────────────

# --- Auth (inline config; not ~/.docker osxkeychain) ---
WATCHTOWER_DOCKER_CONFIG := "config/.watchtower-docker"
WATCHTOWER_DOCKER_CONFIG_FILE := WATCHTOWER_DOCKER_CONFIG + "/config.json"

# Sync config from `gh`; once per machine / after token rotation.
sync-watchtower-ghcr-auth:
    bash scripts/watchtower/sync-ghcr-auth.sh

# Fail if config missing (run sync-watchtower-ghcr-auth first).
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
# Reload compose Watchtower after sync.
restart-watchtower:
    docker compose {{ COMPOSE_FILES }} restart watchtower

# One-shot pull + recreate labeled containers (--debug: progress during pull).
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
