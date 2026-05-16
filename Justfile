TZ := env("TZ", "Europe/Amsterdam")
GIT_DELTA_VERSION := "0.18.2"
PNPM_COREPACK_VERSION := env("PNPM_COREPACK_VERSION", "11.0.9")
YARN_COREPACK_VERSION := env("YARN_COREPACK_VERSION", "4.14.1")
JUST_VERSION := env("JUST_VERSION", "1.36.0")
JUST_LSP_VERSION := env("JUST_LSP_VERSION", "0.3.4")
# Four-layer image chain: base -> tooling -> python -> playwright. Each is published independently in CI.
IMAGE_BASE := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base"
# Adds developer + AI tooling (git-delta, just-lsp, sandbox-runtime, Claude/Codex/Gemini/OpenCode/Tessl) on top of base.
IMAGE_TOOLING := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-tooling"
# Adds Python + uv on top of tooling.
IMAGE_PYTHON := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-python"
# Adds Playwright (Chromium + system deps) on top of python.
IMAGE_PLAYWRIGHT := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-playwright"
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
        --build-arg GIT_DELTA_VERSION="{{ GIT_DELTA_VERSION }}" \
        --build-arg JUST_VERSION="{{ JUST_VERSION }}" \
        --build-arg JUST_LSP_VERSION="{{ JUST_LSP_VERSION }}" \
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

# Create the named volumes referenced by .devcontainer/docker-compose.yml (idempotent).
# Run once on a fresh machine before `just up`; the compose file declares them
# `external: true`, so they must exist before `devcontainer up` / `docker compose up`.
init-volumes:
    #!/usr/bin/env bash
    set -euo pipefail
    for v in claude-config opencode-config opencode-auth cursor-state fish-history ssh-config; do
        name="coding-agent-sandbox-$v"
        if ! docker volume inspect "$name" >/dev/null 2>&1; then
            docker volume create "$name"
        fi
    done

# Start the devcontainer.
up:
    devcontainer up

# Stop the devcontainer.
stop:
    docker stop coding-agent-sandbox-devcontainer

# Remove the devcontainer (stop and delete).
rm:
    docker stop coding-agent-sandbox-devcontainer
    docker rm coding-agent-sandbox-devcontainer

# Enter the devcontainer with a shell (using devcontainer CLI).
enter:
    devcontainer exec fish

# Enter the devcontainer with a shell (using docker exec).
docker-enter:
    docker exec -it coding-agent-sandbox-devcontainer fish

# Pull all images from GitHub Container Registry with latest tag.
pull:
    docker pull {{ IMAGE_BASE }}:latest
    docker pull {{ IMAGE_TOOLING }}:latest
    docker pull {{ IMAGE_PYTHON }}:latest
    docker pull {{ IMAGE_PLAYWRIGHT }}:latest
