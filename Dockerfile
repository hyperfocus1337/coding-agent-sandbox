# syntax=docker/dockerfile:1
# https://github.com/nodejs/docker-node/tree/main/25/trixie
FROM node:25-trixie

# Pass timezone as build argument
ARG TZ
ENV TZ="$TZ"

# Username for the non-root user
ARG USERNAME=node
ARG USER_UID=1000
ARG USER_GID=1000

# Automatically set by BuildKit for multi-platform builds; used to scope apt caches per arch
ARG TARGETARCH

# Install basic development tools
RUN --mount=type=cache,target=/var/cache/apt,id=apt-cache-$TARGETARCH,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,id=apt-lists-$TARGETARCH,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    less \
    git \
    procps \
    sudo \
    fzf \
    fish \
    man-db \
    unzip \
    gnupg2 \
    wget \
    dnsutils \
    jq \
    vim \
    direnv \
    python3 \
    python3-pip \
    python3-venv

# Install Starship prompt
RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes && \
    echo "starship init bash | source" >> ~/.bashrc

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
    chown -R $USERNAME:$USERNAME /usr/local/share

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/$USERNAME/.claude /home/$USERNAME/.local/share/fish && \
    chown -R $USERNAME:$USERNAME /workspace /home/$USERNAME/.claude /home/$USERNAME/.local

WORKDIR /workspace

# Git Delta tool for pretty printing git diffs
ARG GIT_DELTA_VERSION
ENV GIT_DELTA_VERSION="$GIT_DELTA_VERSION"
RUN ARCH=$(dpkg --print-architecture) && \
    wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
    sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
    rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Github CLI
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian
RUN --mount=type=cache,target=/var/cache/apt,id=apt-cache-$TARGETARCH,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,id=apt-lists-$TARGETARCH,sharing=locked \
    (type -p wget >/dev/null || (apt update && apt install wget -y)) \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat $out | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && mkdir -p -m 755 /etc/apt/sources.list.d \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt update \
    && apt install gh -y

# UV package manager (standalone binary)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install Claude Code sandbox runtime
RUN --mount=type=cache,target=/var/cache/apt,id=apt-cache-$TARGETARCH,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,id=apt-lists-$TARGETARCH,sharing=locked \
    --mount=type=cache,target=/root/.npm \
    apt-get update && apt-get install -y bubblewrap socat seccomp && \
    npm install -g @anthropic-ai/sandbox-runtime

# Image version stamp for home-dir initialization tracking (written before USER switch)
ARG IMAGE_VERSION
RUN echo "${IMAGE_VERSION:-unversioned}" > /opt/.devcontainer-version

# Drop to non-root user for runtime
USER $USERNAME

# Rust toolchain (for Justfile LSP)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/$USERNAME/.cargo/bin:$PATH"
RUN --mount=type=cache,target=/home/$USERNAME/.cargo/registry,uid=$USER_UID,gid=$USER_GID \
    --mount=type=cache,target=/home/$USERNAME/.cargo/git,uid=$USER_UID,gid=$USER_GID \
    cargo install cargo-binstall && \
    cargo binstall just-lsp --no-confirm

# Install global npm CLIs as root.
# NPM_CONFIG_PREFIX points to a system path so binaries land in /usr/local/share/npm-global/bin,
# outside $HOME and unaffected by the devcontainer volume mount.
ENV NPM_CONFIG_PREFIX="/usr/local/share/npm-global"
ENV PATH="/usr/local/share/npm-global/bin:/home/$USERNAME/.local/bin:$PATH"

# Install Claude Code CLI official installation script
# https://code.claude.com/docs/en/setup
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Gemini CLI
# https://geminicli.com/docs/get-started/installation/
RUN --mount=type=cache,target=/home/$USERNAME/.npm,uid=${USER_UID},gid=${USER_GID} \
    npm install -g @google/gemini-cli

# Set the default editor and visual
ENV EDITOR="vim"
ENV VISUAL="vim"

# Copy user configurations
COPY --chown=$USERNAME:$USERNAME config/config.fish /home/$USERNAME/.config/fish/config.fish
COPY --chown=$USERNAME:$USERNAME config/.profile /home/$USERNAME/.profile

# Copy scripts into the image
COPY --chown=$USERNAME:$USERNAME scripts/system/activate.fish /home/$USERNAME/scripts/system/activate.fish
COPY --chown=$USERNAME:$USERNAME scripts/agents/ /home/$USERNAME/scripts/agents/

# Pre-seed SSH known_hosts for GitHub
RUN mkdir -p /home/$USERNAME/.ssh && \
    ssh-keyscan github.com >> /home/$USERNAME/.ssh/known_hosts 2>/dev/null

# Install Tessl CLI
RUN curl -fsSL https://get.tessl.io | sh

# Install Claude Code plugins and MCP servers
RUN bash /home/$USERNAME/scripts/agents/claude.sh

# Install Gemini extensions
# RUN bash /home/$USERNAME/scripts/agents/gemini.sh

# Use fish as the container entrypoint (start as login shell with -l)
ENTRYPOINT ["/usr/bin/fish", "-l"]