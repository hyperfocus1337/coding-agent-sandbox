TZ := env("TZ", "Europe/Amsterdam")
GIT_DELTA_VERSION := "0.18.2"
IMAGE := "coding-agent-sandbox-devcontainer"
VERSION := "6.0-trixie"

# Build the devcontainer Docker image and tag it with the current VERSION
build:
    docker build \
        --build-arg TZ={{ TZ }} \
        --build-arg GIT_DELTA_VERSION={{ GIT_DELTA_VERSION }} \
        --build-arg IMAGE_VERSION={{ VERSION }}-`date +%Y%m%d%H%M%S` \
        --tag {{ IMAGE }}:{{ VERSION }} \
        --tag {{ IMAGE }}:latest \
        --file Dockerfile \
        .
