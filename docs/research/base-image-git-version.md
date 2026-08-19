# Investigation: is there a base image with a newer git than debian:trixie-slim?

The devcontainer needs git 2.48 or newer for `worktree.useRelativePaths`. Without it, a worktree created on a macOS host is unusable in the container: its `.git` file points at `/Users/...` instead of a path under `/workspaces`. Debian trixie ships git 2.47.3, so [Dockerfile.tooling](../../Dockerfile.tooling) builds git 2.55.0 from the official kernel.org source tarball (see [apt-packages.md](../tooling/apt-packages.md) and the git block in that Dockerfile).

This note records whether another base image could supply a new enough git from its package manager and let the source build go away.

## Verdict

Keep `debian:trixie-slim` and keep the source build.

Every base image with distribution support caps at git 2.53.0, which is older than the 2.55.0 the source block compiles now. So the block would come back the next time a newer git feature is wanted. The images that do ship 2.55.0 are all rolling releases with no security team, or need every apt block in the five Dockerfiles rewritten for a different package manager.

If the source block must go and a rolling base is acceptable, `debian:sid-slim` is the only swap with no other work: same package names, git 2.55.0, and the `libcurl4-gnutls` conflict that blocked pinning the sid git package into trixie disappears because the whole archive is then consistent. Price: no security support and occasional broken base images.

## git version per candidate image

Checked 2026-08-19 against the [Repology API](https://repology.org/api/v1/project/git), the [Debian sources API](https://sources.debian.org/api/src/git/) and the [Launchpad API](https://api.launchpad.net/1.0/ubuntu/+archive/primary).

| Image                                   | git version | Distribution support | Cost to switch                                   |
| --------------------------------------- | ----------- | -------------------- | ------------------------------------------------ |
| `debian:trixie-slim` (current)          | 2.47.3      | stable, to 2030      | none, but needs the source build for 2.48+       |
| `debian:forky-slim` (testing)           | 2.53.0      | none (testing)       | almost none, same package names                  |
| `debian:sid-slim` (unstable)            | 2.55.0      | none (unstable)      | almost none, same package names                  |
| `ubuntu:26.04` LTS                      | 2.53.0      | LTS, to 2031         | chromium breaks, see below                       |
| `ubuntu:26.10`                          | 2.53.0      | 9 months             | same chromium problem                            |
| `fedora:43` / `fedora:44`               | 2.55.0      | 13 months            | rewrite every apt block for dnf                  |
| `archlinux:base`, `opensuse/tumbleweed` | 2.55.0      | rolling              | full rewrite, different package names and layout |
| `alpine:edge`                           | 2.55.0      | rolling              | full rewrite, plus musl breaks the mise binaries |

Notes on the rejected entries:

- **alpine**: stable Alpine also lags (3.23 has 2.52.0, 3.24 has 2.54.0), but musl is the real blocker. mise installs prebuilt release binaries (node, terraform, kubectl, the aqua and ubi tools) that are linked against glibc, so most would not run.
- **fedora / arch / opensuse**: the git version is current, but every `apt-get install` line, the `extrepo` step that enables the mise repository, and the apt cache mounts would have to be replaced. That is a large change for a tool that is already handled in one `RUN` block.
- **ubuntu:26.04**: the rest of the image fits. `fish 4.2.1`, `neovim 0.11.6` and `extrepo 0.15` are all in `universe`, which the official Ubuntu images enable by default.

## Why the apt options do not work

**No git in trixie-backports.** The Debian sources API lists git in trixie (2.47.3), forky (2.53.0), sid (2.55.0) and experimental only. There is no backport to enable.

**Pinning the sid package into trixie fails.** Tested, not assumed:

```
E: Unable to satisfy dependencies. Reached two conflicting decisions:
   1. git:arm64=1:2.55.0-1 Depends libcurl4-gnutls (>= 8.20.0-3~)
   2. libcurl4-gnutls:arm64 Depends libnghttp3-9 (>= 1.11.0~) but none of the choices are installable
```

This is the Debian time64 transition. trixie has `libcurl3t64-gnutls` 8.14, sid has `libcurl4-gnutls` 8.21, and the newer package declares `Breaks`/`Replaces` on the older one. Installing it would remove `libproxy1v5` (and with it `glib-networking`) and `gstreamer1.0-plugins-bad` (and with it plugins-good and plugins-base).

**Ubuntu has no usable chromium package.** On Ubuntu 26.04 the only source package is `chromium-browser 2:1snap1-0ubuntu4` in `universe`, a transitional package that installs the chromium snap. There is no snapd in the container, so it fails. [Dockerfile.tooling](../../Dockerfile.tooling) installs the Debian `chromium` deb for two reasons: it is arch-correct (puppeteer's own download once fetched an amd64 binary on arm64 and crashed with `Dynamic loader not found: /lib64/ld-linux-x86-64.so.2`), and it ships a SUID `chrome-sandbox`, so headless runs need no `--no-sandbox`. Replacing it with a browser downloaded by puppeteer or playwright loses the sandbox.

## Why mise cannot supply git either

Recorded here because it is the same question from the other side. git publishes no release binaries: `git/git` has zero GitHub release assets, so `ubi:` and `github:` return HTTP 404 on the releases API, and there is no aqua registry entry for it. git is not a mise core tool either (those are bun, deno, dotnet, elixir, erlang, go, java, node, python, ruby, rust, swift, zig). Only a third-party asdf plugin could work, and every such plugin compiles from source anyway, with an unpinned and unverified download. See the git note in [version-management.md](../guides/version-management.md).

## Sources

- git versions per distribution: `https://repology.org/api/v1/project/git`
- git versions per Debian suite: `https://sources.debian.org/api/src/git/`
- Ubuntu package availability and components: `https://api.launchpad.net/1.0/ubuntu/+archive/primary?ws.op=getPublishedSources&source_name=<name>&exact_match=true&distro_series=.../resolute&status=Published`
- Signed tarball hashes for the source build: <https://mirrors.edge.kernel.org/pub/software/scm/git/sha256sums.asc>
