# Investigation: could Homebrew on Linux replace package installs?

> **Update:** the languages and the standalone release binaries have since moved
> to [mise](https://github.com/jdx/mise) (see [version-management.md](version-management.md)).
> That does not contradict this note's verdict against Homebrew: mise is a
> purpose-built polyglot version manager (not a second OS package manager), it
> pins exact versions so builds stay reproducible, and it leaves base OS
> utilities on apt, the agent CLIs on npm, and ruff/oci-cli on uv, exactly as
> argued below. So the "keep on version scripts" recommendations in the tables
> now read as "keep pinned via mise".

This note records whether the packages installed across the Dockerfiles ([Dockerfile.base](../Dockerfile.base), [Dockerfile.node](../Dockerfile.node), [Dockerfile.tooling](../Dockerfile.tooling), [Dockerfile.python](../Dockerfile.python), [Dockerfile.agent](../Dockerfile.agent)) could be installed through Homebrew for Linux instead of their current managers (apt, single-binary downloads, vendor install scripts, npm, and uv).

It started as a narrower question about the version-pinning scripts under [scripts/versions/](../scripts/versions/) (see [version-management.md](version-management.md)) and was widened to every package.

## Verdict

Availability is not the problem. Almost every CLI tool here has a Homebrew formula, and the ones that exist ship Linux bottles for both amd64 and arm64. The problem is fit: Homebrew is the wrong manager for most of these packages, and adopting it costs a large fixed overhead.

- Adopting Linuxbrew adds roughly 400-500 MB before installing a single tool (the brew repo plus the homebrew-core formula clone is about 500 MB; portable-ruby adds about 25 MB). The current static-binary downloads add tens of MB total.
- Homebrew refuses to run as root, while the image installs many packages system-wide as root.
- Each ecosystem already has a better-fit manager: apt for base OS utilities, npm for the agent CLIs, uv for the Python tools, and the pinned [versions.lock](../versions.lock) scripts for the standalone release binaries (which give reproducible builds brew does not).

So no migration is recommended. This is documented so the question is not re-investigated. The findings below are still useful as a reference for what is available, should a single tool ever need it.

## What is actually missing from Homebrew

These have no usable Homebrew-on-Linux path and would block any full migration:

- **just-lsp**: no homebrew-core formula and no known tap. Upstream `terror/just-lsp` ships via cargo / release binaries only. This alone means the version scripts cannot be retired.
- **terraform**: removed from homebrew-core after the BUSL relicense; only via the third-party `hashicorp/tap`, which ships vendored binaries rather than core bottles. The image already prefers OpenTofu (`tofu`, which is in core) anyway.
- **tessl**, **@anthropic-ai/sandbox-runtime**, **@gitlab/duo-cli**, **@playwright/cli**, **claude code**: no formula. npm or vendor-script only.
- **fonts-powerline** and the OpenAI **codex** agent: exist only as casks, which are macOS-only and do not work in a Linux container.
- **sudo**, **patch**: core OS utilities with no homebrew-core formula; provided by the base Debian image.

## Availability by Dockerfile

The tables record whether a formula exists and whether it ships Linux bottles for both arches. "Keep on" is the recommended manager regardless of brew availability.

### Base image (apt utilities plus two binary/script tools)

Every tool below that exists on brew ships both `x86_64_linux` and `arm64_linux` bottles (or an arch-independent bottle), verified live against the formulae.brew.sh JSON API.

| Tool                                                                                                                  | brew formula                         | On brew (core)? | Recommended manager                                        |
|-----------------------------------------------------------------------------------------------------------------------|--------------------------------------|-----------------|------------------------------------------------------------|
| git, less, curl, wget, gnupg, unzip, tree, fzf, fish, neovim, direnv, jq                                              | same names                           | yes             | keep on apt (base OS / lighter)                            |
| ripgrep, fd-find, bat, shellcheck, universal-ctags, patchutils, miller, csvkit, httpie, socat, moreutils, ncdu, rsync | `fd` for fd-find; rest same          | yes             | keep on apt                                                |
| dnsutils                                                                                                              | `bind`                               | yes             | keep on apt                                                |
| netcat-openbsd                                                                                                        | `netcat`                             | yes             | keep on apt (brew ships GNU netcat, a behavior difference) |
| file                                                                                                                  | `file-formula`                       | yes             | keep on apt                                                |
| postgresql-client                                                                                                     | `libpq` (keg-only) or `postgresql@N` | partial         | keep on apt                                                |
| procps, man-db, strace, lsof, ca-certificates                                                                         | various                              | yes             | keep on apt (base OS)                                      |
| sudo, patch                                                                                                           | none                                 | no              | apt only (no brew formula)                                 |
| yq                                                                                                                    | `yq`                                 | yes             | currently a github binary; brew works but adds no value    |
| starship                                                                                                              | `starship`                           | yes             | currently vendor script; brew works but adds no value      |

### Tooling image

| Tool                                                               | current method | brew                                                                        | Linux bottles | Recommended manager                                            |
|--------------------------------------------------------------------|----------------|-----------------------------------------------------------------------------|---------------|----------------------------------------------------------------|
| gh                                                                 | apt keyring    | core `gh`                                                                   | yes           | keep (apt path is vendor-documented)                           |
| glab                                                               | binary script  | core `glab`                                                                 | yes           | keep on version scripts (pinned)                               |
| git-delta                                                          | binary script  | core `git-delta`                                                            | yes           | keep on version scripts (pinned)                               |
| just                                                               | binary script  | core `just`                                                                 | yes           | keep on version scripts (pinned)                               |
| just-lsp                                                           | binary script  | none                                                                        | n/a           | keep on version scripts (no brew)                              |
| terraform                                                          | binary script  | tap only (BUSL)                                                             | n/a           | keep on version scripts; prefer OpenTofu                       |
| OpenTofu (tofu)                                                    | apt            | core `opentofu`                                                             | yes           | keep on apt                                                    |
| yamllint, shellcheck                                               | apt            | core                                                                        | yes           | keep on apt                                                    |
| azure-cli (az)                                                     | vendor script  | core `azure-cli`                                                            | yes           | keep (vendor-documented)                                       |
| aws-cli v2                                                         | vendor bundle  | core `awscli`                                                               | yes           | keep (vendor-documented)                                       |
| bubblewrap, socat, libseccomp                                      | apt            | core                                                                        | yes           | keep on apt (sandbox deps)                                     |
| fonts-powerline                                                    | apt            | cask only (macOS)                                                           | n/a           | keep on apt                                                    |
| herdr                                                              | vendor script  | core `herdr`                                                                | yes           | brew is an option, but vendor script installs integrations too |
| tessl                                                              | vendor script  | none                                                                        | n/a           | keep (vendor script only)                                      |
| prettier, eslint, markdownlint-cli2                                | npm            | core (noarch `all` bottle wrapping npm)                                     | n/a           | keep on npm (brew lags, just wraps npm)                        |
| sandbox-runtime, codex, gemini-cli, opencode, duo-cli, claude code | npm / script   | mixed: gemini-cli and opencode have real core bottles; others npm/cask/none | varies        | keep on npm / vendor script (current releases, not lagged)     |

### Python image

| Tool                  | current method           | brew                                     | Linux bottles | Recommended manager                                          |
|-----------------------|--------------------------|------------------------------------------|---------------|--------------------------------------------------------------|
| python3 (+ pip, venv) | apt                      | core `python@3.x` (bundles pip and venv) | yes           | keep on apt                                                  |
| uv, uvx               | copied from astral image | core `uv`                                | yes           | keep (pinned copy from official image)                       |
| ruff                  | uv tool                  | core `ruff`                              | yes           | keep on uv (good brew candidate too, but uv keeps it pinned) |
| oci-cli               | uv tool                  | core `oci-cli`                           | yes           | keep on uv (isolated venv, pinnable)                         |

### Playwright image

| Tool                               | current method          | brew                                                                                      | Notes                                                                  |
|------------------------------------|-------------------------|-------------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| playwright (Python pkg + Chromium) | uv run                  | no formula                                                                                | keep on uv; browser binaries come from `playwright install` regardless |
| @playwright/cli                    | npm                     | `playwright-cli` exists but is the abandoned `@playwright/cli@0.1.14`, not the modern CLI | keep on npm; the brew formula is a stale trap                          |
| cloakbrowser                       | uv tool (commented out) | no formula                                                                                | keep on uv                                                             |

## Why keep each ecosystem on its own manager

- **apt** for base OS utilities and sandbox deps: already present in the `node:trixie` base, no extra runtime, smaller than brew, and these are foundational tools where a newer version buys nothing.
- **npm** for the agent CLIs (prettier, eslint, codex, gemini-cli, opencode, duo-cli, sandbox-runtime, claude): brew formulae for npm tools are often absent, lag releases, or are just noarch wrappers around npm. npm tracks the current release.
- **uv** for the Python tools (ruff, oci-cli, playwright, cloakbrowser): isolated per-tool venvs, pinnable, decoupled from whatever Python brew would pull in as a dependency.
- **version scripts** for the standalone release binaries (glab, git-delta, just, just-lsp, terraform): reproducible pinned builds via [versions.lock](../versions.lock), which `brew install` cannot match, and just-lsp has no formula at all.

## Sources

- Formula availability and Linux bottles verified live against `https://formulae.brew.sh/api/formula/<name>.json` (`bottle.stable.files` keys `x86_64_linux` / `arm64_linux`).
- [git-delta](https://formulae.brew.sh/formula/git-delta), [glab](https://formulae.brew.sh/formula/glab), [just](https://formulae.brew.sh/formula/just)
- terraform removed from core (BUSL); [hashicorp/homebrew-tap](https://github.com/hashicorp/homebrew-tap)
- brew bootstrap size: [Slimming down Homebrew for Docker images](https://discourse.brew.sh/t/slimming-down-installation-for-docker-images/7890), [homebrew/brew image](https://hub.docker.com/r/homebrew/brew/)
