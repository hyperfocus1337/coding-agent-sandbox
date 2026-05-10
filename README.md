# Dev Container

This directory defines a [Dev Container](https://containers.dev/) environment for any coding agent project.

## Contents

| Path                             | Description                                                                                                                                                                                                          |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Dockerfile`                     | Image based on [`node:26-trixie`](https://github.com/nodejs/docker-node/tree/main/26/trixie). Installs development tools, Claude Code CLI, Gemini CLI, Tessl CLI, GitHub CLI, and git-delta.                         |
| `playwright`                     | Child image on top of the devcontainer: Playwright system deps and Chromium (`PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`). `BASE_IMAGE` selects the base (default `…/devcontainer:latest`; CI pins digest after push). |
| `.devcontainer/`                 | VS Code / Cursor Dev Container configuration (optional; this repo often gitignores this tree locally).                                                                                                               |
| `config/config.fish`             | Fish shell configuration (Starship prompt, direnv hook, PATH).                                                                                                                                                       |
| `scripts/agents/claude.sh`       | Installs Claude Code plugins and MCP servers (Context7, Tessl, GitHub).                                                                                                                                              |
| `scripts/agents/gemini.sh`       | Gemini CLI extensions (CLI is installed in the Dockerfile; this script is commented out there).                                                                                                                      |
| `docs/sharing-claude-history.md` | Notes for migrating Claude Code conversation history across machines or Docker volumes.                                                                                                                              |
| `Justfile`                       | Convenience commands for building the images and common container tasks.                                                                                                                                             |

## Justfile

Run `just` from the **repository root** (where `Dockerfile` and `Justfile` live).

### Build the images

```bash
just build
```

This runs **`build-base`** then **`build-playwright`**: it builds `Dockerfile` and the `playwright` child image. Defaults tag both `IMAGE` and `IMAGE_PLAYWRIGHT` with `VERSION` (default `local`) and `latest` — for example `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer:local` and `…/devcontainer-playwright:local`, plus `:latest` for each.

Use **`just build-base`** or **`just build-playwright`** alone when you only need one layer (for example, after pulling a published base from GHCR).

The `playwright` Dockerfile accepts **`BASE_IMAGE`** (must match the devcontainer you extend). `just build-playwright` sets it to `IMAGE` with tag `latest` so overrides to `IMAGE` still stack locally.

The base `Dockerfile` does **not** embed Corepack semver defaults; `just build` and CI pass them via build args.

In **GitHub Actions** (`.github/workflows/docker-devcontainer.yml`), the workflow builds and pushes **both** images to GHCR: `ghcr.io/<owner>/<repo>/devcontainer` and `…/devcontainer-playwright`, using the same metadata-driven tags (branch, PR, semver, SHA, `latest` on the default branch). After the base image is pushed, the Playwright build uses that base **digest** so the child image matches exactly. On **pull requests** the base image is not pushed, so the Playwright stage builds from **`devcontainer:latest`** on GHCR to validate the `playwright` Dockerfile (it does not layer on an unpublished PR base).

Repository **variables** supply `GIT_DELTA_VERSION`, `PNPM_COREPACK_VERSION`, `YARN_COREPACK_VERSION`, and `JUST_LSP_VERSION` (**Settings → Secrets and variables → Actions → Variables**); keep those aligned with the Justfile defaults when you bump pins.

SSH client config uses the optional BuildKit secret `ssh_config` (same mechanism locally and in GitHub Actions: repo secret `SSH_CONFIG` → `secret-files`). If the secret is missing or empty, the image is built without `~/.ssh/config` (known_hosts for `github.com` is still added).

The following variables can be overridden at invocation time (see the `Justfile` for the full list):

| Variable                | Default                                                               | Description                                                                                                                                                          |
| ----------------------- | --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TZ`                    | `Europe/Amsterdam` (or `$TZ` from the environment)                    | Timezone baked into the image                                                                                                                                        |
| `GIT_DELTA_VERSION`     | `0.18.2`                                                              | Version of [git-delta](https://github.com/dandavison/delta) to install                                                                                               |
| `PNPM_COREPACK_VERSION` | `11.0.9`                                                              | Pinned semver for `pnpm` (Corepack `prepare`)                                                                                                                        |
| `YARN_COREPACK_VERSION` | `4.14.1`                                                              | Pinned semver for Yarn Berry (Corepack `prepare`)                                                                                                                    |
| `JUST_LSP_VERSION`      | `0.3.4`                                                               | [just-lsp](https://github.com/terror/just-lsp) release tag; set matching **Actions variable** for CI builds                                                          |
| `IMAGE`                 | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer`            | Registry/repository path for the base `docker build` tags                                                                                                            |
| `IMAGE_PLAYWRIGHT`      | `ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-playwright` | Registry/repository path for the Playwright child image (`playwright` Dockerfile)                                                                                    |
| `VERSION`               | `local`                                                               | Primary image tag for **both** images (also written into `IMAGE_VERSION` for the base image stamp)                                                                   |
| `SUDO_PASSWORD_FILE`    | `config/.sudo-password`                                               | Optional one-line disposable password file; passed as secret `container_user_password` so it does **not** land in image history                                      |
| `SSH_CONFIG_FILE`       | `config/.ssh/config`                                                  | If this path exists and is non-empty, it is passed as secret `ssh_config`; otherwise the build skips SSH client config (mirrors unset/empty `SSH_CONFIG` in Actions) |

Example — override the timezone:

```bash
just TZ=UTC build
```

### Sudo password for ad-hoc package installs

The base Node image does not put `node` in the `sudo` group or set a login password. The image adds `node` to `sudo` and, if BuildKit secret `container_user_password` is provided (`just build` forwards `SUDO_PASSWORD_FILE` when that path exists), sets a disposable login password via `chpasswd`.

Use a **throwaway** one-line secret only. Prefer a gitignored file (default `config/.sudo-password`), not repeated command-line literals. The build strips CR/LF line endings from that file so Windows-style `CRLF` does not change the password versus what you type.

**The running image must have been built with the secret.** A `prebuild` or `:latest` pull from GHCR only has a password if CI set the `CONTAINER_USER_PASSWORD` secret when that image was built; your local `config/.sudo-password` is not read at runtime. To confirm whether `node` has a password, run `docker exec -u root -it <container-name> passwd -S node` (`P` means a password is set; `NP` / locked means `sudo` auth will always fail until you rebuild with the secret or run `passwd node` as root).

```bash
printf '%s\n' 'your-dev-only-secret' > config/.sudo-password
just build
```

If that file is absent, password-based `sudo` is unavailable until a root-capable step sets one, for example:

```bash
docker exec -u root -it coding-agent-sandbox-devcontainer passwd node
```

For **GitHub Actions** builds, optionally add a repository secret `CONTAINER_USER_PASSWORD` (same one-line throwaway value); the workflow writes it to a BuildKit secret so the image gets an interactive `sudo` password without a `--build-arg`. Leave the secret unset to skip (typical for CI).
