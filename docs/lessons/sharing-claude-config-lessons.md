# Lessons Learned: Sharing Claude Config Between Host and Devcontainer

## What Was Attempted

Bind-mounting the host `~/.claude` directory into a devcontainer:

```json
"source=${localEnv:HOME}/.claude,target=/home/user/.claude,type=bind"
```

The intent was to share Claude settings, MCP server configs, and installed plugins between the host machine and the container without duplication.

---

## Why It Doesn't Work

### 1. Plugin Paths Are Absolute and Host-Specific

Claude Code plugins (installed via `claude mcp add` or similar) store **absolute paths** inside `~/.claude`. These paths point to locations on the **host filesystem** (e.g. `/Users/you/.npm-global/...` or `/home/you/.nvm/...`) that do not exist inside the container, causing resolution failures at startup or plugin invocation.

### 2. Node/npm Binary Paths Diverge

Plugin entries reference Node.js, npx, or npm binaries via their host paths. The container may have these at entirely different locations (or different versions), so even if the file exists by name, the runtime path is wrong.

### 3. Filesystem UID/GID Mismatches

The bind mount shares ownership from the host. If the container user (`node`, uid 1000) differs from the host user's uid, Claude config files may be read-only or cause permission errors when Claude tries to write session state or update settings.

### 4. Config Is Tightly Coupled to the Environment

`~/.claude` conflates two concerns that need to be separated:

- **Portable config** (preferences, themes, API key reference) — safe to share
- **Environment-specific state** (plugin paths, binary references, session cache) — must be per-environment

Bind-mounting the entire directory imports the environment-specific parts wholesale, making the container config broken by default.

---

## Recommended Approach

| Concern            | Strategy                                                                                                                      |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------|
| API key            | Pass via `ANTHROPIC_API_KEY` env var (devcontainer `containerEnv`)                                                            |
| MCP server config  | Maintain a separate `~/.claude/claude_desktop_config.json` (or equivalent) inside the container, with container-correct paths |
| Plugins            | Re-install inside the container using container-local paths; do not bind-mount from host                                      |
| Shared preferences | Copy only the portable parts (e.g. `settings.json`) into the image at build time via `COPY` or a `postCreateCommand` script   |

---

## Bottom Line

The bind mount approach creates a false sense of reuse. Claude's config directory stores environment-coupled state, so sharing it verbatim across different filesystems causes path resolution errors. The container needs its own `~/.claude` initialised with container-correct paths, while secrets are injected via environment variables.
