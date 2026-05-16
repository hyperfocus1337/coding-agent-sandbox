# `.devcontainer/`

Defines the dev environment for this repo, split across three files:

| File                          | Owns                                                                                                                                                                                                                                                                                                        |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `docker-compose.yml`          | **Runtime container shape**: image, container name, env, ports, shared volumes, lifetime. Anything `docker compose up` needs to recreate the environment without VS Code.                                                                                                                                   |
| `docker-compose.override.yml` | **Per-machine bind mounts** (local repo paths). Gitignored so private filesystem layouts stay out of version control. Compose auto-merges this file with `docker-compose.yml` when both sit side by side. A `docker-compose.override.yml.example` is committed as a template — copy it on a fresh checkout. |
| `devcontainer.json`           | **Editor integration**: which compose service to attach to, where the workspace lives inside the container, plus VS Code/Cursor-only features (extensions, settings, port labels, port forwarding UI).                                                                                                      |

The split lets the same container be brought up two ways:

- **Editor-driven** — open the repo in VS Code or Cursor → *Reopen in Container*. The IDE reads `devcontainer.json`, which points at `docker-compose.yml`.
- **Plain Docker** — `docker compose -f .devcontainer/docker-compose.yml up -d`. No editor required; useful for headless agents, CI smoke tests, or just `docker exec` shells.

## `docker-compose.yml`

```yaml
name: coding-agent-sandbox
services:
  sandbox:
    image: …/devcontainer-playwright:latest
    container_name: coding-agent-sandbox-devcontainer
    command: sleep infinity
    environment: { … }
    ports: [ … ]
    volumes: [ … ]
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
- **Top-level `name:` and `networks.default.name:`** — compose defaults the *project name* to the directory the compose file sits in (here `.devcontainer/` → `devcontainer`) and prefixes every auto-named resource with it (e.g. network `devcontainer_default`). Pinning `name: coding-agent-sandbox` at the top of the compose file and `networks.default.name: coding-agent-sandbox-network` under the network block strips that prefix from every resource the file owns. Combined with `container_name` on the service and `external: true` on each named volume (which makes compose use the literal key as the volume name instead of prefixing it), nothing in this stack carries a `devcontainer_` prefix.
- **Workspace bind `..:/workspaces/coding-agent-sandbox:cached`** — when the devcontainer CLI starts a container from an `image:` field it auto-binds the workspace. In `dockerComposeFile` mode it does **not** — the bind must be declared explicitly here, otherwise the in-container workspace folder is empty.
- **Named volumes declared `external: true`** — compose normally prefixes named volumes with the compose project name (e.g. `devcontainer_coding-agent-sandbox-claude-config`). `external: true` tells compose to skip the prefix and reuse a pre-existing volume of the literal name. This preserves Claude config, OpenCode auth tokens, fish history, cursor-server install, etc. across rebuilds, and silences compose's "volume already exists but was not created by Docker Compose" warning (it stamps labels on volumes it creates; pre-existing ones lack those labels). The cost: on a fresh machine the volumes must be created manually before `devcontainer up` — run `just init-volumes` from the repo root for an idempotent create-if-missing pass. `docker compose down -v` will not remove external volumes either, so deliberate teardown also goes through `docker volume rm`.
- **`:delegated` / `:cached` / `:ro`** — macOS/Windows bind-mount performance hints (or read-only); no-op on Linux. `:cached` = host authoritative, container's view may lag; `:delegated` = container authoritative, host's view may lag; `:ro` = read-only. One-to-one with the older `consistency=cached` / `consistency=delegated` / `readonly` mount options. See the header comment in `docker-compose.override.yml` for the rationale on the per-machine binds.

## `docker-compose.override.yml`

Holds bind mounts that point at host directories specific to one developer's filesystem layout (e.g. `~/Repositories/your-org/repo-a`). Gitignored.

Compose merges this file with `docker-compose.yml` automatically when both live in the same directory. `devcontainer.json` lists both via `dockerComposeFile`, so the editor sees the merged result too. The `volumes:` list under `services.sandbox` is *appended*, not replaced — committed `docker-compose.yml` keeps owning the shared mounts (workspace bind, named volumes, the SSH key), and the override only adds extra bind mounts on top.

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
|-------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `name`                  | Display name in the VS Code / Cursor *Reopen in Container* picker. No Docker equivalent.                                                                                                                                                                                   |
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

## Adding a new mount

Decide which file based on whether the mount is shared or per-machine:

- **Shared** (same on every developer's machine — named volumes, the workspace bind, an SSH key at a canonical path) → `docker-compose.yml`.
- **Per-machine** (a host path that depends on where *you* keep your repos) → `docker-compose.override.yml`.

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
