# Mounting host projects into the devcontainer

The devcontainer mounts your host repositories into `/workspaces` through bind mounts declared in [`.devcontainer/docker-compose.override.yml`](../../.devcontainer/docker-compose.override.yml). Each project is one line under `services.sandbox.volumes`:

```yaml
- ${HOME}/Repositories/agents/my-project:/workspaces/my-project:delegated
```

The `:delegated` consistency flag lets the container's writes flush asynchronously instead of blocking on every fsync, a big win for node_modules-heavy or git-heavy repos on macOS/Windows (on Linux it is a no-op). See the header comment in the override file for the other modes.

## Adding a project

Use the `add-project` recipe instead of editing the file by hand:

```bash
just add-project agents/my-project
```

It appends the bind mount and prints how to apply it: `just up` recreates the container with the new path mounted, killing whatever runs inside it. `cas add` does the same but asks first, listing the Claude sessions the recreate would kill. The last path segment (`my-project`) becomes the `/workspaces` target.

The `PROJECT` argument is a path under `~/Repositories`. All three forms normalize to the same entry, so you can tab-complete a full path and it still works:

```bash
just add-project agents/my-project
just add-project ~/Repositories/agents/my-project
just add-project /Users/you/Repositories/agents/my-project
```

A relative path is taken as a repo under `~/Repositories`; an absolute path is mounted from where it lives, so `just add-project ~/.local/share/chezmoi` works too. Paths inside your home directory are written back as `${HOME}/...`, which compose expands at `up` time, so the override stays portable.

## Consistency flag

`:delegated` is the default. Override it with a second argument when a project needs stricter host/container consistency:

```bash
just add-project folder-path/project-path cached
```

Modes: `consistent` (default docker behavior, slow), `cached` (host authoritative), `delegated` (container authoritative).

## Dedup

Re-running `add-project` for a path that is already mounted with the same consistency flag prints `already mounted: <project>`, skips the append and exits 3, which is how `cas add` knows there is nothing to apply. The check keys on the full line, so re-adding the same project with a different consistency flag will append a second entry (change the existing line by hand if that is not what you want).
