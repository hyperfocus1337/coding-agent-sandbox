TZ := env("TZ", "Europe/Amsterdam")
GIT_DELTA_VERSION := "0.18.2"
PNPM_COREPACK_VERSION := env("PNPM_COREPACK_VERSION", "11.0.9")
YARN_COREPACK_VERSION := env("YARN_COREPACK_VERSION", "4.14.1")
IMAGE := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer"
VERSION := "local"
SSH_CONFIG_FILE := "config/.ssh/config"

# Optional: Dockerfile sets `$USERNAME`'s Unix password via `CONTAINER_USER_PASSWORD` so `sudo apt install …`
# works inside the container. The upstream node image puts `node` in neither `sudo` nor a password-bearing state by default.
#
# Prefer a disposable dev-only value: build args may be visible via `docker image history`. Omit it for CI or when
# packages are baked in via root RUN lines instead.
#
# Set when building, e.g. `CONTAINER_USER_PASSWORD=secret just build`.
# Without it here, sudo is unusable until you set a password from a root context, e.g.
# `docker exec -u root -it coding-agent-sandbox-devcontainer passwd node`.
export CONTAINER_USER_PASSWORD := env("CONTAINER_USER_PASSWORD", "")

# Build the devcontainer Docker image and tag it with the current VERSION
build:
    #!/usr/bin/env bash
    set -euo pipefail
    PASSWORD_ARGS=()
    if [[ -n "${CONTAINER_USER_PASSWORD}" ]]; then
        PASSWORD_ARGS+=(--build-arg "CONTAINER_USER_PASSWORD=${CONTAINER_USER_PASSWORD}")
    fi
    docker build \
        "${PASSWORD_ARGS[@]}" \
        --build-arg TZ="{{ TZ }}" \
        --build-arg GIT_DELTA_VERSION="{{ GIT_DELTA_VERSION }}" \
        --build-arg PNPM_COREPACK_VERSION="{{ PNPM_COREPACK_VERSION }}" \
        --build-arg YARN_COREPACK_VERSION="{{ YARN_COREPACK_VERSION }}" \
        --build-arg IMAGE_VERSION="{{ VERSION }}-$(date +%Y%m%d%H%M%S)" \
        --secret id=ssh_config,src="{{ SSH_CONFIG_FILE }}" \
        --tag "{{ IMAGE }}:{{ VERSION }}" \
        --tag "{{ IMAGE }}:latest" \
        --file Dockerfile \
        .

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
