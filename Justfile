# ──────────────────────────────────────────────────────────────────────────────
# Variables (shared across sections)
# ──────────────────────────────────────────────────────────────────────────────

# Running devcontainer container name. Used by Container lifecycle, Shell access,
# Agent sessions, Setup and Projects.
CONTAINER := "coding-agent-sandbox-devcontainer"

# Both compose files, in override-last order. Used by Container lifecycle and Watchtower.
# The override is also read and written by scripts/projects/lib.sh, which has the path.
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

# Mounts are baked into a container when it is created, so `restart-compose` below
# never applies a mount that was added since. This converges compose first, which
# recreates the container when its config changed, and bounces it only when compose
# left it alone. A stopped container is started.
# Restart the devcontainer so it comes back with the current compose config.
[group('lifecycle')]
restart:
    @bash scripts/container/restart.sh {{ CONTAINER }}

# `restart` above is enough when the compose config changed. This is the way to recycle
# a container whose config did not, so compose would leave it alone.
# Delete the container and start a fresh one, even when the compose config is unchanged.
[group('lifecycle')]
recreate:
    @docker rm -f {{ CONTAINER }} 2>/dev/null || true
    @just up

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

# Reuses the existing container, so it cannot apply a new mount. Use `restart` above
# unless that is what you want.
# Restart the devcontainer with raw `docker compose restart` (no recreate).
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
#
# -w takes the directory, so this needs no `cd` inside the shell, and the argument can
# be a project or any path under one. The default `.` resolves to itself, which is
# /workspaces, the container WORKDIR: `just cd` with no argument lands there.
# Open a fish shell in the container (e.g. `just cd my-project`, or bare for /workspaces).
[group('access')]
[no-exit-message]
cd PROJECT_NAME=".":
    @p="$(just resolve-project '{{ PROJECT_NAME }}')" && docker exec -it -u user -w "/workspaces/$p" {{ CONTAINER }} fish

# The script is passed as the bash -c argument, so it needs no mount of this repo inside
# the container and keeps stdin free for the tools it runs. The report names accounts
# and hosts, so it lands in docs/host/, which is gitignored.
# Write a Markdown overview of the access glab, gh, aws, az, oci and SSH have in the container.
[group('access')]
access-overview:
    @mkdir -p docs/host && docker exec -u user {{ CONTAINER }} bash -c "$(cat scripts/container/access-overview.sh)" > docs/host/access-overview.md && echo "wrote docs/host/access-overview.md"

# ──────────────────────────────────────────────────────────────────────────────
# Agent sessions
# ──────────────────────────────────────────────────────────────────────────────

# -e TERM_PROGRAM lets the containerized Claude emit its own terminal notification,
# which cmux renders; the cmux Claude wrapper cannot reach into the container.
# See docs/guides/cmux-notifications.md.
# ARGS are forwarded to claude, which is what the resume recipes below use; the
# transcripts they resume from live in the claude-config volume, so they survive a stop.
# Step into a project directory and run Claude there (e.g. `just claude my-project`).
[group('sessions')]
[no-exit-message]
claude PROJECT_NAME *ARGS:
    @p="$(just resolve-project '{{ PROJECT_NAME }}')" && docker exec -it -u user -e TERM_PROGRAM {{ CONTAINER }} fish -C "cd $p; claude --dangerously-skip-permissions {{ ARGS }}"

# RESUME is prefixed to each session id, so cas passes its own resume command and the
# lines it prints stay pasteable. The script prints nothing when no session is running,
# which is how cas tells that from a probe it could not make, so the message for that
# case is added here.
# List the Claude sessions running in the container, with how to resume each.
[group('sessions')]
[no-exit-message]
sessions RESUME="just resume-session":
    @out="$(bash scripts/sessions/list.sh {{ CONTAINER }} "{{ RESUME }}")" && printf '%s\n' "${out:-No Claude sessions running in {{ CONTAINER }}.}"

# Claude reports it itself if that project has no session yet.
# Continue a project's most recent session (e.g. `just resume my-project`).
[group('sessions')]
[no-exit-message]
resume PROJECT_NAME:
    @just claude {{ PROJECT_NAME }} --continue

# Resuming by id ignores the cwd, so this lands in /workspaces (`cd .` from the
# container WORKDIR) and needs no project name.
# Resume one exact session by id, as printed by `just sessions`.
[group('sessions')]
[no-exit-message]
resume-session SESSION_ID:
    @just claude . --resume {{ SESSION_ID }}

# --- Codex ---

# Same shape as `claude` above: the bypass flag is Codex's equivalent of
# --dangerously-skip-permissions, and the container is the sandbox it asks for.
# Codex keeps its state in ~/.codex, a named volume, so its sessions survive a stop.
# Step into a project directory and run Codex there (e.g. `just codex my-project`).
[group('sessions')]
[no-exit-message]
codex PROJECT_NAME *ARGS:
    @p="$(just resolve-project '{{ PROJECT_NAME }}')" && docker exec -it -u user -e TERM_PROGRAM {{ CONTAINER }} fish -C "cd $p; codex --dangerously-bypass-approvals-and-sandbox {{ ARGS }}"

# `codex resume` filters its picker by cwd, so --last from the project dir is that
# project's most recent session. Codex reports it itself when there is none.
# Codex has no counterpart to `claude agents`, so there is no `codex-sessions`
# recipe and no way to resume one exact Codex session by id from here. Run
# `just codex <project> resume` for Codex's own picker instead.
# Continue a project's most recent Codex session (e.g. `just codex-resume my-project`).
[group('sessions')]
[no-exit-message]
codex-resume PROJECT_NAME:
    @just codex {{ PROJECT_NAME }} resume --last

# --- Pi ---

# Same shape as `claude` above. Pi runs its tools without an approval prompt; the one
# thing it asks about is the project-local .pi/ files (extensions, skills), and --approve
# trusts them, since the container is the sandbox. Pi keeps its sessions in ~/.pi, a
# named volume, so they survive a stop.
# Step into a project directory and run Pi there (e.g. `just pi my-project`).
[group('sessions')]
[no-exit-message]
pi PROJECT_NAME *ARGS:
    @p="$(just resolve-project '{{ PROJECT_NAME }}')" && docker exec -it -u user -e TERM_PROGRAM {{ CONTAINER }} fish -C "cd $p; pi --approve {{ ARGS }}"

# Pi stores sessions per cwd, so --continue from the project dir is that project's
# most recent session. Pi reports it itself when there is none. Like Codex, Pi has no
# session index to read ids from here; `just pi <project> --resume` opens its own picker.
# Continue a project's most recent Pi session (e.g. `just pi-resume my-project`).
[group('sessions')]
[no-exit-message]
pi-resume PROJECT_NAME:
    @just pi {{ PROJECT_NAME }} --continue

# ──────────────────────────────────────────────────────────────────────────────
# Setup (fresh machine, after a rebuild)
# ──────────────────────────────────────────────────────────────────────────────

# Run once on a fresh machine before `just up`; the compose file declares them
# `external: true`, so they must exist before `devcontainer up` / `docker compose up`.
# Create the named volumes referenced by .devcontainer/docker-compose.yml (idempotent).
[group('setup')]
init-volumes:
    #!/usr/bin/env bash
    set -euo pipefail
    for v in claude-config gitlab-duo-config gitlab-cli-config aws-cli-config azure-cli-config oracle-cli-config opencode-config opencode-auth cursor-state vscode-state fish-history ssh-config gemini-config codex-config pi-config agents-config ccstatusline-config; do
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

# ──────────────────────────────────────────────────────────────────────────────
# Projects (the bind mounts under /workspaces)
# ──────────────────────────────────────────────────────────────────────────────

# A project is one bind mount: a directory on the host, mounted as one directory under
# /workspaces in the container. The first two recipes read the mounts, the last three
# change them. See docs/guides/mounting-projects.md.

# The mounted projects are the dirs under /workspaces in the container, which is what
# the agents see. A mount added since the container was created is in the override and
# not there yet.
# List the mounted projects.
[group('projects')]
projects:
    @bash scripts/projects/list.sh {{ CONTAINER }}

# Used by `claude`, `codex` and `cd` above, so an unmounted name is one message instead
# of an agent running in /workspaces on the whole tree. `org/repo` and
# ~/Repositories/org/repo both resolve to the mount `repo`, and anything after it is
# kept, so `org/repo/src` resolves to `repo/src`.
#
# CLI names the front end the refusal points at, since cas has its own names for the
# listing and the mount command. cas passes `cas`.
# no-exit-message: "not mounted" is an answer, not a failed recipe. Keep the description
# below it, just takes the last comment line as its `--list` text.
# Resolve a project name to its path under /workspaces, or refuse it.
[group('projects')]
[no-exit-message]
resolve-project PROJECT CLI="just":
    @bash scripts/projects/resolve.sh {{ CONTAINER }} "{{ PROJECT }}" {{ CLI }}

# The three recipes below edit the mounts. Their logic lives in scripts/projects/,
# whose lib.sh owns the override path and the mount line format. All three are prefixed
# with `@`: `cas` calls them and shows what they print, so the echoed command line would
# be noise in its output.

# PROJECT is a path under ~/Repositories (`agents/my-project`) or any absolute
# path; its last segment becomes the /workspaces target. Exits 3 when that mount
# is already there. See docs/guides/mounting-projects.md.
# no-exit-message: that exit 3 is a normal outcome, not a failed recipe. Keep the
# description below it, just takes the last comment line as its `--list` text.
# Append a project bind mount to the compose override (apply it with `just up`).
[group('projects')]
[no-exit-message]
add-project PROJECT CONSISTENCY="delegated":
    @bash scripts/projects/add-project.sh "{{ PROJECT }}" "{{ CONSISTENCY }}"

# PROJECT is a mounted project, named by its /workspaces directory the way `cas list`
# shows it. Prints the host directory it is mounted from, so a caller can show what a
# rename moves before it moves it. Exits 1 when nothing is mounted under that name.
# no-exit-message: "not mounted" is an answer, not a failed recipe. Keep the
# description below it, just takes the last comment line as its `--list` text.
# Print the host directory a mounted project comes from.
[group('projects')]
[no-exit-message]
project-source PROJECT:
    @bash scripts/projects/project-source.sh "{{ PROJECT }}"

# Renames in both places at once: the directory on the host, and the /workspaces name the
# agents see. Renaming only one leaves the other pointing at a name that is gone, and
# docker recreates a mount whose source is missing as an empty dir on the host.
#
# NEW is one directory name, not a path: the directory keeps its parent. Exits 2 on a bad
# name, and 1 when OLD is not mounted, NEW already is, or the directories are not in the
# state a rename needs. Applying it is the caller's job, with `just up`.
# no-exit-message: those refusals are answers, not failed recipes. Keep the description
# below it, just takes the last comment line as its `--list` text.
# Rename a mounted project on the host and in /workspaces.
[group('projects')]
[no-exit-message]
rename-project OLD NEW:
    @bash scripts/projects/rename-project.sh "{{ OLD }}" "{{ NEW }}"

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
