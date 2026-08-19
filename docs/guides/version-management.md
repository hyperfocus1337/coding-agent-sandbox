# Tool and language version management

Languages (Node, Python) and the pinned release binaries (git-delta, glab, just, just-lsp, terraform, yq, starship, gitleaks, betterleaks) plus the package managers (pnpm, yarn, uv) are all installed and pinned through [mise](https://github.com/jdx/mise). This replaces the old hand-rolled system (`versions.lock` + `scripts/versions/{manifest,install,resolve}.sh`) and the Corepack dance.

## How it works

mise is installed once in `Dockerfile.base` via Debian's `extrepo` (the vendor-recommended [Docker recipe](https://github.com/jdx/mise/blob/main/docs/mise-cookbook/docker.md)). Its data and config live outside `$HOME` so the baked-in tools survive the devcontainer's `$HOME` volume mounts:

```dockerfile
ENV MISE_DATA_DIR="/usr/local/share/mise"
ENV MISE_CONFIG_DIR="/usr/local/share/mise"
ENV PATH="/usr/local/share/mise/shims:$PATH"
```

Every version lives in one file: [`mise.toml`](../../mise.toml) at the repo root. `Dockerfile.base` COPYs it in as mise's global config (`/usr/local/share/mise/config.toml`), then each layer materializes only its subset with `mise install <tools>`, reading the pins from that config:

| Layer                | `mise install …`                                                                |
| -------------------- | ------------------------------------------------------------------------------- |
| `Dockerfile.base`    | `yq`, `starship`                                                                |
| `Dockerfile.node`    | `node`, `pnpm`, `yarn`                                                          |
| `Dockerfile.tooling` | `glab`, `just`, `terraform`, `git-delta`, `just-lsp`, `gitleaks`, `betterleaks` |
| `Dockerfile.python`  | `python`, `uv`                                                                  |

`mise install <tool>` installs the tool into `MISE_DATA_DIR` at the version pinned in `mise.toml` and writes a shim onto `PATH`. Because the shims dir is on `PATH`, the tools resolve in any shell without activation; `config.fish` additionally runs `mise activate fish` so a developer can `mise use` new tools at runtime.

Managing versions from one file outside the container is the point: edit `mise.toml`, rebuild, done. It beats build-args (which would spread `ARG` declarations across three Dockerfiles plus the Justfile and CI) because mise reads the file natively with no glue.

## Backends

Most tools resolve by short name through mise's built-in [registry](https://mise.jdx.dev/registry.html) (`mise registry` lists them). Two use an explicit backend:

- **git-delta** — `aqua:dandavison/delta@<ver>` (its registry short name is `delta`; the explicit aqua backend is unambiguous).
- **just-lsp** — `ubi:terror/just-lsp@<ver>`. It is not in the registry, so the `ubi` backend downloads and extracts the GitHub release binary directly, which is exactly what the retired `install.sh` did.

## Common tasks

**Pin or change a version.** Edit the tool's line in `mise.toml` and rebuild. That file is the single source of truth (the role `versions.lock` used to play).

**See newer versions.** In a running container, `mise outdated` shows what is available. Update `mise.toml` to match, then rebuild.

**Add a new tool.** Add a `<tool> = "<version>"` line to `mise.toml`, then add the tool name to the `mise install …` call in the appropriate layer (base for prompt/data tools, node for Node runtimes, tooling for dev binaries, python for Python tooling). If the short name is not in the registry, use an explicit backend as the key (`"aqua:owner/repo"`, `"ubi:owner/repo"`, `github:`, `gitlab:`).

## What is deliberately not on mise

**git** is the notable one. Trixie's apt git is 2.47.3 and `worktree.useRelativePaths` needs 2.48+, but no mise backend can install a newer one: git publishes no release binaries (`git/git` has zero GitHub release assets, and aqua has no entry), so `aqua:`/`ubi:`/`github:` have nothing to download, and git is not a mise core tool. The only mise route is a plugin that compiles from source, which means running third-party bash or vendoring a plugin of our own. Neither is worth it for one tool, so `Dockerfile.tooling` builds git from the official kernel.org tarball in a single block, with `GIT_VERSION` and two sha256 hashes pinned as `ARG`s there. Debian sid's 2.55.0 package was rejected: it depends on `libcurl4-gnutls`, which `Breaks` trixie's `libcurl3t64-gnutls` and would remove `libproxy1v5`, `glib-networking` and the gstreamer plugins with it.

Base OS utilities stay on apt, the agent CLIs stay on npm, and ruff/oci-cli stay on uv. See [brew-research.md](../lessons/brew-research.md) for the per-ecosystem reasoning; mise owns the languages and the version-pinned-binary niche, which is where it fits best.
