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

The path is resolved and checked before anything is written, so `.`, `..` and a trailing slash all settle to one form, and a directory that does not exist is refused with `no such directory`. Both matter, because neither is an error at `up` time: docker creates a missing bind source as an empty directory on the host. `~/Repositories` itself is refused too, since mounting the whole tree over `/workspaces` makes docker create one empty directory there per sibling mount.

The recipe resolves a relative path against `~/Repositories`, not against your shell, so `just add-project .` names the tree and is refused. `cas add .` mounts the directory you are in: it resolves the path in your shell first, where the working directory is known.

## Renaming a project

Renaming a repo on the host without the mount leaves the mount pointing at a path that is gone, and docker recreates it as an empty directory. `rename-project` does both at once:

```bash
just rename-project my-project my-project-v2
```

`OLD` is the `/workspaces` name. `NEW` is one directory name, not a path: the directory keeps its parent, so `~/Repositories/agents/my-project` becomes `~/Repositories/agents/my-project-v2`. The mount line keeps its indent and its consistency flag. Apply it with `just up`, or use `cas rename`, which previews both paths, asks, and lists the Claude sessions the restart would kill.

It refuses to act when `OLD` is not mounted, when `NEW` is already mounted, when the source is not a directory, or when the target name is taken on disk. Nothing is moved or rewritten in those cases.

`project-source` answers the read-only half of the same question:

```bash
just project-source my-project
```

It prints the host directory the mount comes from, with `${HOME}` expanded. The source is not always named after the project: `chezmoi` is mounted from `~/.local/share/chezmoi`, so renaming that project moves chezmoi's own source directory.

## Consistency flag

`:delegated` is the default. Override it with a second argument when a project needs stricter host/container consistency:

```bash
just add-project folder-path/project-path cached
```

Modes: `consistent` (default docker behavior, slow), `cached` (host authoritative), `delegated` (container authoritative).

## Dedup

Re-running `add-project` for a path that is already mounted with the same consistency flag prints `already mounted: <project>`, skips the append and exits 3, which is how `cas add` knows there is nothing to apply. The check keys on the full line, so re-adding the same project with a different consistency flag will append a second entry (change the existing line by hand if that is not what you want). `rename-project` refuses a project in that state, since it cannot tell which of the two lines to rewrite.

## Where the logic lives

The recipes are one line each in the [`Justfile`](../../Justfile). They run the scripts in [`scripts/projects/`](../../scripts/projects), which are also runnable on their own. `lib.sh` there holds the override path and the mount line format, so a change to the line shape is one edit that the three mount editors follow.

Two more scripts in that folder answer questions about the mounts instead of changing them, and both `just` and `cas` call them:

- `list.sh`, behind `just projects` and `cas list`, lists the directories under `/workspaces` in the container. That is what the agents see, so a mount added since the container was created is in the override and not in the listing.
- `resolve.sh`, behind `just resolve-project`, turns a project name into its path under `/workspaces` and refuses a name that is not mounted. `just claude`, `just codex` and `just cd` resolve their argument through it, so an unmounted name is one message instead of an agent running in `/workspaces` on the whole tree. `cas` passes `cas` as the second argument, which is what makes the refusal name `cas list` instead of `just projects`.
