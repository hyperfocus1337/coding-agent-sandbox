TZ := env("TZ", "Europe/Amsterdam")
GIT_DELTA_VERSION := "0.18.2"
IMAGE := "ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer"
VERSION := "local"
SSH_CONFIG_FILE := "config/.ssh/config"

# Build the devcontainer Docker image and tag it with the current VERSION
build:
    docker build \
        --build-arg TZ={{ TZ }} \
        --build-arg GIT_DELTA_VERSION={{ GIT_DELTA_VERSION }} \
        --build-arg IMAGE_VERSION={{ VERSION }}-`date +%Y%m%d%H%M%S` \
        --secret id=ssh_config,src={{ SSH_CONFIG_FILE }} \
        --tag {{ IMAGE }}:{{ VERSION }} \
        --tag {{ IMAGE }}:latest \
        --file Dockerfile \
        .
