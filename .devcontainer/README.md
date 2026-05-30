# `.devcontainer/`

Defines the dev environment for this repo, split across three files:

| File                          | Owns                                                                                                                                                                                                                                                                                                        |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docker-compose.yml`          | **Runtime container shape**: image, container name, env, ports, shared volumes, lifetime. Anything `docker compose up` needs to recreate the environment without VS Code.                                                                                                                                   |
| `docker-compose.override.yml` | **Per-machine bind mounts** (local repo paths). Gitignored so private filesystem layouts stay out of version control. Compose auto-merges this file with `docker-compose.yml` when both sit side by side. A `docker-compose.override.yml.example` is committed as a template — copy it on a fresh checkout. |
| `devcontainer.json`           | **Editor integration**: which compose service to attach to, where the workspace lives inside the container, plus VS Code/Cursor-only features (extensions, settings, port labels, port forwarding UI).                                                                                                      |

The split lets the same container be brought up in two ways.

- **Editor-driven** — open the repo in VS Code or Cursor → _Reopen in Container_. The IDE reads `devcontainer.json`, which points at `docker-compose.yml`.
- **Plain Docker** — `docker compose -f .devcontainer/docker-compose.yml up -d`. No editor required; useful for headless agents, CI smoke tests, or just `docker exec` shells.

## Why the split?

If you're not using VS Code, Cursor, or GitHub Codespaces you can ignore `devcontainer.json` entirely — `docker-compose.yml` alone is enough. The split exists because `devcontainer.json` owns capabilities compose has no equivalent for:

- Installs VS Code / Cursor extensions inside the container on attach.
- Applies editor workspace settings (`editor.formatOnSave`, linter config, etc.) to the in-container IDE server.
- Labels forwarded ports so they show up named in the IDE's _Ports_ panel.
- Sets the remote user the IDE connects as (`remoteUser`).
- Runs dev-workflow lifecycle hooks: `postCreateCommand`, `postStartCommand`, `postAttachCommand`.
- Works natively with GitHub Codespaces with zero extra config.
- Pulls in devcontainer _features_ — one-liners to add full toolchains (Node, Python, AWS CLI, …) without writing Dockerfile layers.

You don't have to pick one or the other. `devcontainer.json` delegates the actual container definition to compose via `dockerComposeFile`, so compose owns infrastructure (image, volumes, networks, ports, lifetime) and `devcontainer.json` owns the developer-experience layer on top. The split keeps each file responsible for one concern: edit compose to change _what runs_, edit `devcontainer.json` to change _how the editor attaches to it_.

There's also a practical lifecycle win from going through compose: a plain image-based devcontainer (the `"image": "..."` style in `devcontainer.json`, no compose) makes you delete and rebuild the container by hand every time you add a mount, since mounts are baked in at creation time. Docker Compose detects the config change on the next `up -d`, recreates the container itself, and skips the manual `docker rm` step. A plain `docker compose up -d` gets this behavior — see [Applying changes to compose config](#applying-changes-to-compose-config) for the full mechanics.

If you want to add a volume without recreating the container, add it in `docker-compose.override.yml` and run `docker compose up -d` again before rerunning `devcontainer up` or reopening the editor.

If you ever drop VS Code / Cursor / Codespaces from the workflow, you can delete `devcontainer.json` and keep using compose unchanged.

## `docker-compose.yml`

```yaml
name: coding-agent-sandbox
services:
  sandbox:
    image: …/devcontainer-playwright:latest
    container_name: coding-agent-sandbox-devcontainer
    command: sleep infinity
    environment: { … }
    ports: […]
    volumes: […]
volumes:
  coding-agent-sandbox-*:
    external: true
networks:
  default:
    name: coding-agent-sandbox-network
```

Key choices:

- **`command: sleep infinity`** — keeps PID 1 alive so the editor (or `docker exec`) has something to attach to. The base image declares its login shell via `CMD ["/usr/bin/fish", "-l"]` rather than `ENTRYPOINT`, so this `command:` cleanly replaces the default. (With `ENTRYPOINT`, `sleep infinity` would be appended as args — `fish -l sleep infinity` — and the container would exit 127.)
- **`container_name`** — pins the container to `coding-agent-sandbox-devcontainer` so the `Justfile` recipes (`just stop`, `just rm`, `just docker-enter`) keep working. Without it, compose would generate a name like `devcontainer-sandbox-1`.
- **Top-level `name:` and `networks.default.name:`** — compose defaults the _project name_ to the directory the compose file sits in (here `.devcontainer/` → `devcontainer`) and prefixes every auto-named resource with it (e.g. network `devcontainer_default`). Pinning `name: coding-agent-sandbox` at the top of the compose file and `networks.default.name: coding-agent-sandbox-network` under the network block strips that prefix from every resource the file owns. Combined with `container_name` on the service and `external: true` on each named volume (which makes compose use the literal key as the volume name instead of prefixing it), nothing in this stack carries a `devcontainer_` prefix.
- **Workspace bind `..:/workspaces/coding-agent-sandbox:cached`** — when the devcontainer CLI starts a container from an `image:` field it auto-binds the workspace. In `dockerComposeFile` mode it does **not** — the bind must be declared explicitly here, otherwise the in-container workspace folder is empty.
- **Named volumes declared `external: true`** — compose normally prefixes named volumes with the compose project name (e.g. `devcontainer_coding-agent-sandbox-claude-config`). `external: true` tells compose to skip the prefix and reuse a pre-existing volume of the literal name. This preserves Claude config, OpenCode auth tokens, fish history, cursor-server install, etc. across rebuilds, and silences compose's "volume already exists but was not created by Docker Compose" warning (it stamps labels on volumes it creates; pre-existing ones lack those labels). The cost: on a fresh machine the volumes must be created manually before `devcontainer up` — run `just init-volumes` from the repo root for an idempotent create-if-missing pass. `docker compose down -v` will not remove external volumes either, so deliberate teardown also goes through `docker volume rm`.
- **`:delegated` / `:cached` / `:ro`** — macOS/Windows bind-mount performance hints (or read-only); no-op on Linux. `:cached` = host authoritative, container's view may lag; `:delegated` = container authoritative, host's view may lag; `:ro` = read-only. One-to-one with the older `consistency=cached` / `consistency=delegated` / `readonly` mount options. See the header comment in `docker-compose.override.yml` for the rationale on the per-machine binds.

## Watchtower (container auto-updates)

A second compose service, `watchtower`, polls the registry and recreates the `sandbox` container when a newer image is pushed. It talks to the daemon over the mounted `/var/run/docker.sock`.

```yaml
watchtower:
  image: ghcr.io/nicholas-fedor/watchtower:latest
  restart: unless-stopped
  environment:
    WATCHTOWER_LABEL_ENABLE: "true" # only touch opted-in containers
    WATCHTOWER_CLEANUP: "true" # prune the old image after update
    WATCHTOWER_POLL_INTERVAL: "21600" # 6h
    DOCKER_CONFIG: /config
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - ../config/.watchtower-docker:/config:ro
```

### GHCR authentication (private packages)

Host `docker pull` can use `~/.docker/config.json` with `credsStore: osxkeychain` (empty `"ghcr.io": {}` entries). Watchtower runs in a Linux container and **cannot** call `docker-credential-osxkeychain`, so it needs a separate config with **inline** `auth` for `ghcr.io` only.

One-time (or after PAT rotation):

```bash
just sync-watchtower-ghcr-auth   # writes config/.watchtower-docker/config.json from gh
just watchtower-auth-check       # verify the file exists
just restart-watchtower          # if Watchtower was already running
```

`config/.watchtower-docker/config.json` is gitignored; `config.json.example` shows the shape. Requires `gh` logged in; the token needs `read:packages` for private GHCR. If `just sync-watchtower-ghcr-auth` prints a scope warning, run `gh auth refresh -s read:packages` in a terminal (browser OAuth — do not run that inside the sync script or it looks like a hang).

Key choices:

- **Use a maintained fork, not the original.** The upstream `containrrr/watchtower` was archived in December 2025 (last release `1.7.1`, image built 2023-11). Its bundled Docker client defaults to API `1.25` and fails to negotiate against a modern daemon, so every poll errors with `client version 1.25 is too old. Minimum supported API version is 1.40` (this daemon advertises `1.40` via `docker version` → `Server.MinAPIVersion`). The old workaround was to pin `DOCKER_API_VERSION: "1.40"` and skip negotiation. Instead this stack uses [`nickfedor/watchtower`](https://github.com/nicholas-fedor/watchtower), an actively maintained drop-in fork built against a current client — it negotiates the API automatically, so no pin is needed and the env var is gone.
- **Opt-in by label** — `WATCHTOWER_LABEL_ENABLE=true` scopes Watchtower to containers carrying `com.centurylinklabs.watchtower.enable=true`. Only `sandbox` has that label, so nothing else on the host is ever recreated. Drop the env var to watch _every_ container instead.

Minimal functional setup is the image, socket mount, and GHCR auth directory; label scoping, cleanup, and interval are tuning:

```yaml
watchtower:
  image: ghcr.io/nicholas-fedor/watchtower:latest
  restart: unless-stopped
  environment:
    DOCKER_CONFIG: /config
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - ../config/.watchtower-docker:/config:ro
```

Watchtower comes up alongside the rest of the stack whenever you run `just up`. After `just sync-watchtower-ghcr-auth`:

```bash
just up                         # apply config (brings the whole stack up, watchtower included)
just update                     # one-shot pull + recreate (needs watchtower-auth-check)
just restart-watchtower         # reload auth after sync-watchtower-ghcr-auth
docker logs coding-agent-sandbox-watchtower
docker exec coding-agent-sandbox-watchtower /watchtower --run-once  # same as just update (in-container)
```

Caveat: `sandbox` runs `command: sleep infinity`, so when Watchtower updates it the container is recreated and any attached IDE / devcontainer session drops. If that bites, remove the enable label from `sandbox` and update by hand, or widen `WATCHTOWER_POLL_INTERVAL`.

## `docker-compose.override.yml`

Holds bind mounts that point at host directories specific to one developer's filesystem layout (e.g. `~/Repositories/your-org/repo-a`). Gitignored.

Compose merges this file with `docker-compose.yml` automatically when both live in the same directory. `devcontainer.json` lists both via `dockerComposeFile`, so the editor sees the merged result too. The `volumes:` list under `services.sandbox` is _appended_, not replaced — committed `docker-compose.yml` keeps owning the shared mounts (workspace bind, named volumes, the SSH key), and the override only adds extra bind mounts on top.

Fresh checkout:

```bash
cp .devcontainer/docker-compose.override.yml.example .devcontainer/docker-compose.override.yml
# edit it: point each entry at a real host path you want exposed inside the container
```

If you don't need any extra mounts, the file can be a stub:

```yaml
services:
  sandbox:
    volumes: []
```

The file must exist on disk — `devcontainer.json` references it explicitly, so a missing file aborts `devcontainer up`.

## `devcontainer.json`

```jsonc
{
  "name": "Coding Agent Sandbox",
  "dockerComposeFile": ["docker-compose.yml", "docker-compose.override.yml"],
  "service": "sandbox",
  "workspaceFolder": "/workspaces/coding-agent-sandbox",
  "remoteUser": "node",
  "forwardPorts": [ … ],
  "portsAttributes": { … },
  "customizations": { "vscode": { … } }
}
```

What each field does and why it lives here rather than in compose:

| Field                   | Why it stays in `devcontainer.json`                                                                                                                                                                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`                  | Display name in the VS Code / Cursor _Reopen in Container_ picker. No Docker equivalent.                                                                                                                                                                                   |
| `dockerComposeFile`     | Tells the IDE to start the container via compose instead of `docker run`. Path is relative to this file.                                                                                                                                                                   |
| `service`               | Which compose service to attach to. Required whenever `dockerComposeFile` is set, even if there's only one service.                                                                                                                                                        |
| `workspaceFolder`       | Where the IDE opens its file explorer inside the container. Must match the in-container path of the workspace bind in compose. Compose itself doesn't know which mount is "the workspace" — this field tells the IDE.                                                      |
| `remoteUser`            | UID the IDE runs its server process under. Compose has `user:` but the IDE may need to override per-attach (e.g. for a different user when running tasks vs. opening a terminal).                                                                                          |
| `forwardPorts`          | VS Code's port forwarding panel — auto-forwards listed ports out of the container on attach. Separate from compose `ports`, which only handles host publishing. With both, compose publishes for host browsers and the IDE forwards for remote-SSH / Codespaces scenarios. |
| `portsAttributes`       | Labels for the Ports panel (e.g. `3000 → "Node"`). UI metadata only — no compose equivalent.                                                                                                                                                                               |
| `customizations.vscode` | Extensions to install in the IDE server and editor settings to apply on attach. Lives in the IDE, not the container, so it has no place in compose.                                                                                                                        |

Fields that intentionally **do not** appear here:

- `image`, `runArgs`, `mounts`, `containerEnv` → moved to compose.
- `appPort` → not supported alongside `dockerComposeFile`. Replaced by compose `ports`.

## Usage

```bash
# Build images locally (run from repo root, see ../Justfile).
just build

# First time on a fresh machine: create the external named volumes.
just init-volumes

# Bring the container up via devcontainer CLI (editor-equivalent path).
just up

# Or via plain compose (works without the devcontainer CLI).
docker compose -f .devcontainer/docker-compose.yml up -d

# Shell in.
just docker-enter         # docker exec into running container
# or: just enter          # via devcontainer CLI

# Stop / remove.
just stop
just rm
```

## Applying changes to compose config

Mounts, env vars, ports, and image references are baked into a container at _creation_ time, so `docker start` on an existing container reuses its original config and ignores anything you've edited since. The container has to be recreated for new config to take effect — and how painful that is depends on whether your devcontainer is image-based or compose-based.

A plain image-based devcontainer (the `"image": "..."` style in `devcontainer.json`, no compose) makes you do the work by hand: delete the container and let the IDE rebuild it from scratch every time you add a mount. Docker Compose is smarter — it hashes the desired service config from `docker-compose.yml` + `docker-compose.override.yml`, compares it against the existing container, and if they differ it stops the old one and starts a fresh one with the new config on the next `up -d`. No manual `docker rm` step.

Because this repo's `devcontainer.json` delegates to compose via `dockerComposeFile`, both `just up` and plain `docker compose up -d` get the compose behavior automatically.

```bash
# Edit docker-compose*.yml, then either:
just up                                                     # devcontainer CLI → compose up -d
docker compose -f .devcontainer/docker-compose.yml up -d    # plain compose
```

Compose will print `Recreating coding-agent-sandbox-devcontainer ... done` when it detects a diff. To force a recreate even when config is unchanged (e.g. after rebuilding the image):

```bash
docker compose -f .devcontainer/docker-compose.yml up -d --force-recreate
```

Caveats:

- **Named volumes** survive recreation (data persists). **Anonymous volumes and the writable container layer do not** — anything written outside a mount is lost on recreate.
- Plain `docker run` / `docker start` workflows do not get this auto-recreate behavior. There you'd `docker rm` + `docker run` again by hand. Stick to compose (directly or via `devcontainer up`) and this concern goes away.

## Adding a new mount

Decide which file based on whether the mount is shared or per-machine:

- **Shared** (same on every developer's machine — named volumes, the workspace bind, an SSH key at a canonical path) → `docker-compose.yml`.
- **Per-machine** (a host path that depends on where _you_ keep your repos) → `docker-compose.override.yml`.

Then:

1. Add a line under `services.sandbox.volumes:` in the chosen file.
   - Bind mount: `${HOME}/path/on/host:/path/in/container:delegated`
   - Named volume: `my-volume-name:/path/in/container`
2. For a new named volume, also declare it under the top-level `volumes:` block in `docker-compose.yml` with `external: true`, and add the suffix (e.g. `new-thing`) to the `init-volumes` recipe in the root `Justfile` so fresh machines pick it up.
3. If the mount is the kind every contributor will want, mirror the entry into `docker-compose.override.yml.example` so newcomers see it in the template.

## Adding a new published port

1. Add `"NNNN:NNNN"` under `services.sandbox.ports:` in `docker-compose.yml`.
2. Add `NNNN` to `forwardPorts` in `devcontainer.json` (so the IDE forwards it on remote attach).
3. Optionally add a label under `portsAttributes`.
