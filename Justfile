TZ := env("TZ", "Europe/Amsterdam")
GIT_DELTA_VERSION := "0.18.2"
PNPM_COREPACK_VERSION := env("PNPM_COREPACK_VERSION", "11.0.9")
YARN_COREPACK_VERSION := env("YARN_COREPACK_VERSION", "4.14.1")
JUST_LSP_VERSION := env("JUST_LSP_VERSION", "0.3.4")
IMAGE := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer"
# Extends the base devcontainer image with Playwright (Chromium + system deps).
IMAGE_PLAYWRIGHT := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-playwright"
VERSION := "local"
SSH_CONFIG_FILE := "config/.ssh/config"

# Optional: one-line file with a disposable Unix password for `$USERNAME` (BuildKit secret
# `container_user_password`; not stored in image history like a `--build-arg`). Omit for CI.
SUDO_PASSWORD_FILE := "config/.sudo-password"

# Base devcontainer image (tags :latest for the Playwright stage FROM).
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
        --build-arg GIT_DELTA_VERSION="{{ GIT_DELTA_VERSION }}" \
        --build-arg PNPM_COREPACK_VERSION="{{ PNPM_COREPACK_VERSION }}" \
        --build-arg YARN_COREPACK_VERSION="{{ YARN_COREPACK_VERSION }}" \
        --build-arg JUST_LSP_VERSION="{{ JUST_LSP_VERSION }}" \
        --build-arg IMAGE_VERSION="{{ VERSION }}-$(date +%Y%m%d%H%M%S)" \
        --tag "{{ IMAGE }}:{{ VERSION }}" \
        --tag "{{ IMAGE }}:latest" \
        --file Dockerfile \
        .

# Playwright layer on top of {{ IMAGE }}:latest (run after build-base or publish of :latest).
build-playwright:
    docker build \
        --build-arg BASE_IMAGE="{{ IMAGE }}:latest" \
        --tag "{{ IMAGE_PLAYWRIGHT }}:{{ VERSION }}" \
        --tag "{{ IMAGE_PLAYWRIGHT }}:latest" \
        --file playwright \
        .

# Build the base devcontainer image and the Playwright-extended image.
build: build-base build-playwright

up:
    devcontainer up

stop:
    docker stop coding-agent-sandbox-devcontainer

rm:
    docker stop coding-agent-sandbox-devcontainer
    docker rm coding-agent-sandbox-devcontainer

enter:
    devcontainer exec fish

docker-enter:
    docker exec -it coding-agent-sandbox-devcontainer fish
