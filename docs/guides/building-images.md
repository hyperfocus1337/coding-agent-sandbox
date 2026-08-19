# Building the images

Run `just` from the **repository root** (where `Dockerfile.base` and `Justfile` live).

## Build everything

```bash
just build
```

This runs **`build-base`** → **`build-node`** → **`build-tooling`** → **`build-python`** → **`build-agent`**, producing five images tagged with `VERSION` (default `local`) and `latest`:

- `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base:{VERSION,latest}`
- `…/devcontainer-node:{VERSION,latest}`
- `…/devcontainer-tooling:{VERSION,latest}`
- `…/devcontainer-python:{VERSION,latest}`
- `…/devcontainer-agent:{VERSION,latest}`

## Building a single layer

Use **`just build-base`**, **`just build-node`**, **`just build-tooling`**, **`just build-python`**, or **`just build-agent`** alone when you only need one layer (for example, after pulling a published parent from GHCR).

## Selecting the base image

`Dockerfile.node`, `Dockerfile.tooling`, `Dockerfile.python`, and `Dockerfile.agent` accept **`BASE_IMAGE`** (must match the layer you extend). The recipes wire each child to the prior layer's `:latest` tag locally so overrides to `IMAGE_BASE`/`IMAGE_NODE`/`IMAGE_TOOLING`/`IMAGE_PYTHON` still stack.

## Tool and language versions

Languages (Node, Python), package managers (pnpm, yarn, uv), and the pinned release binaries (git-delta, glab, just, just-lsp, terraform, yq, starship, gitleaks, betterleaks) are all installed and version-pinned via [mise](https://github.com/jdx/mise). Every version lives in one file, [`mise.toml`](../../mise.toml) at the repo root, which is COPY'd into the base image as mise's global config; each layer installs its subset with `mise install`. To bump a version, edit `mise.toml` and rebuild. See [version-management.md](version-management.md) for the per-layer breakdown, backends, and adding tools. git is the one exception: it has no binary release for mise to fetch, so `Dockerfile.tooling` compiles it from the official tarball with the version and hashes pinned in that block's `ARG`s.

## GitHub Actions builds

In **GitHub Actions** (`.github/workflows/docker-devcontainer.yml`), five independent jobs (`build-base`, `build-node`, `build-tooling`, `build-python`, `build-agent`) each build and push their own image to GHCR with metadata-driven tags (branch, PR, semver, SHA, `latest` on the default branch). Each job is a separate runner: `devcontainer-base` is pushed and pullable the moment its job finishes, regardless of whether the downstream `node`/`tooling`/`python`/`agent` jobs are still running or have failed. Downstream jobs pin **`BASE_IMAGE`** to the upstream **digest** so child images match exactly. On **pull requests** images are not pushed, so the downstream jobs fall back to the parent's `:latest` tag on GHCR for Dockerfile validation.

Tool and language versions are not build-args: they are pinned in `mise.toml` and installed per layer with `mise install` (see [version-management.md](version-management.md)).

## Personal state (runtime, not baked)

The images ship with **no** personal state, so they are safe to publish. Git identity, SSH client config, SSH keys and the `sudo` password are injected at runtime through gitignored bind mounts in `.devcontainer/docker-compose.override.yml` (copy `docker-compose.override.yml.example` and edit the paths). The base image only seeds `~/.ssh/known_hosts` for `github.com`; the sudo password is applied by `entrypoint.sh` from a root-only mount (see [sudo-password.md](sudo-password.md)). See [mounting-projects.md](mounting-projects.md) for the override pattern.

## Overridable variables

The following variables can be overridden at invocation time (see the `Justfile` for the full list):

| Variable        | Default                                                            | Description                                                                                            |
| --------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| `TZ`            | `Europe/Amsterdam` (or `$TZ` from the environment)                 | Timezone baked into the image                                                                          |
| `IMAGE_BASE`    | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base`    | Registry/repository path for the base image (`Dockerfile.base`)                                        |
| `IMAGE_NODE`    | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-node`    | Registry/repository path for the Node child image (`Dockerfile.node`)                                  |
| `IMAGE_TOOLING` | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-tooling` | Registry/repository path for the tooling child image (`Dockerfile.tooling`)                            |
| `IMAGE_PYTHON`  | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-python`  | Registry/repository path for the Python + Playwright child image (`Dockerfile.python`)                 |
| `IMAGE_AGENT`   | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-agent`   | Registry/repository path for the agent top image (`Dockerfile.agent`)                                  |
| `VERSION`       | `local`                                                            | Primary image tag for **all five** images (also written into `IMAGE_VERSION` for the base image stamp) |

Example, override the timezone:

```bash
just TZ=UTC build
```
