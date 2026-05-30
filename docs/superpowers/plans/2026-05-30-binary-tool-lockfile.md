# Binary tool lockfile installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the five duplicated, three-way-pinned binary tool installs in `Dockerfile.tooling` with a single committed `versions.lock`, a shared `install.sh` helper driven by a `manifest.sh`, and a `resolve.sh` resolver run via `just lock`.

**Architecture:** A root-level `versions.lock` (env-style) is the single source of truth for versions. `scripts/versions/manifest.sh` holds static per-tool metadata (source, URL template, arch map, install method) as a sourced bash file. `scripts/versions/install.sh <name>` reads both, expands the URL, downloads, and installs by method (deb / tar / zip). `scripts/versions/resolve.sh` queries upstream "latest" and rewrites `versions.lock`. Builds read the pinned lock (reproducible, no build-time API calls); the resolver is a manual dev step.

**Tech Stack:** Bash, Docker/BuildKit, GitHub Actions, Just, `curl`, `jq`, `dpkg`, `tar`, `unzip`.

**Spec:** `docs/superpowers/specs/2026-05-30-binary-tool-lockfile-design.md`

---

## File structure

- Create: `versions.lock` — repo root. Pinned versions, env-style `KEY=value`.
- Create: `scripts/versions/manifest.sh` — sourced metadata: `tool_meta`, `tool_arch`, `ALL_TOOLS`.
- Create: `scripts/versions/install.sh` — `install.sh <name>` (and `install.sh --print-url <name>` for offline testing).
- Create: `scripts/versions/resolve.sh` — `resolve.sh [lockpath]`, rewrites `versions.lock`.
- Create: `scripts/versions/test_versions.sh` — offline assertions for manifest + install URL expansion + resolve parsing (with stubbed fetch).
- Modify: `Dockerfile.tooling` — COPY the helper + lock; replace the 5 tool `RUN` blocks with `install-tool <name>`; drop the per-tool `ARG *_VERSION`.
- Modify: `Justfile` — remove the 5 `*_VERSION :=` lines and the 5 `--build-arg *_VERSION`; add a `lock` recipe.
- Modify: `.github/workflows/docker-devcontainer.yml` — drop the 4 tooling `--build-arg *_VERSION` and the "keep aligned" comment block.

The exact-URL regression guard: `test_versions.sh` asserts the expanded URLs equal the URLs currently hardcoded in `Dockerfile.tooling`, so the refactor cannot silently change a download path.

---

### Task 1: versions.lock (single source of truth)

**Files:**
- Create: `versions.lock`

- [ ] **Step 1: Create the lockfile with current pinned values**

These five values are the ones currently in `Justfile` (git-delta, just, just-lsp, terraform) and the `GLAB_VERSION` added earlier.

`versions.lock`:

```sh
# Pinned versions for binary tools installed in Dockerfile.tooling.
# Single source of truth. Regenerate with `just lock`; edit a line to override.
GIT_DELTA_VERSION=0.18.2
GLAB_VERSION=1.100.0
JUST_VERSION=1.36.0
JUST_LSP_VERSION=0.3.4
TERRAFORM_VERSION=1.15.3
```

- [ ] **Step 2: Verify it sources cleanly**

Run: `bash -c 'set -eu; . ./versions.lock; echo "$GIT_DELTA_VERSION $GLAB_VERSION $JUST_VERSION $JUST_LSP_VERSION $TERRAFORM_VERSION"'`
Expected: `0.18.2 1.100.0 1.36.0 0.3.4 1.15.3`

- [ ] **Step 3: Commit**

```bash
git add versions.lock
git commit -m "feat: add versions.lock as single source of truth for binary tools"
```

---

### Task 2: manifest.sh (static metadata)

**Files:**
- Create: `scripts/versions/manifest.sh`

- [ ] **Step 1: Write the manifest**

`scripts/versions/manifest.sh`:

```sh
# shellcheck shell=bash
# Static metadata for binary tools. Sourced, not executed.
# tool_meta <name> sets: KIND REPO TAG_PREFIX METHOD URL_TMPL VERSION_VAR DEST MEMBER
# URL_TMPL is a literal template containing ${VERSION} and ${ARCH} (single-quoted, not expanded here).

ALL_TOOLS="git-delta glab just just-lsp terraform"

tool_meta() {
  case "$1" in
    git-delta)
      KIND=github; REPO=dandavison/delta; TAG_PREFIX=""; METHOD=deb
      URL_TMPL='https://github.com/dandavison/delta/releases/download/${VERSION}/git-delta_${VERSION}_${ARCH}.deb'
      VERSION_VAR=GIT_DELTA_VERSION; DEST=""; MEMBER="" ;;
    glab)
      KIND=gitlab; REPO=gitlab-org/cli; TAG_PREFIX="v"; METHOD=deb
      URL_TMPL='https://gitlab.com/gitlab-org/cli/-/releases/v${VERSION}/downloads/glab_${VERSION}_linux_${ARCH}.deb'
      VERSION_VAR=GLAB_VERSION; DEST=""; MEMBER="" ;;
    just)
      KIND=github; REPO=casey/just; TAG_PREFIX=""; METHOD=tar
      URL_TMPL='https://github.com/casey/just/releases/download/${VERSION}/just-${VERSION}-${ARCH}.tar.gz'
      VERSION_VAR=JUST_VERSION; DEST="$HOME/.local/bin"; MEMBER="just" ;;
    just-lsp)
      KIND=github; REPO=terror/just-lsp; TAG_PREFIX=""; METHOD=tar
      URL_TMPL='https://github.com/terror/just-lsp/releases/download/${VERSION}/just-lsp-${VERSION}-${ARCH}.tar.gz'
      VERSION_VAR=JUST_LSP_VERSION; DEST="$HOME/.local/bin"; MEMBER="./just-lsp" ;;
    terraform)
      KIND=hashicorp; REPO=""; TAG_PREFIX=""; METHOD=zip
      URL_TMPL='https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_${ARCH}.zip'
      VERSION_VAR=TERRAFORM_VERSION; DEST="$HOME/.local/bin"; MEMBER="terraform" ;;
    *)
      echo "Unknown tool: $1" >&2; return 1 ;;
  esac
}

# tool_arch <name> <dpkg-arch> -> vendor arch string on stdout, empty if unsupported.
tool_arch() {
  case "$1" in
    git-delta|glab|terraform)
      case "$2" in amd64) echo amd64 ;; arm64) echo arm64 ;; *) echo "" ;; esac ;;
    just)
      case "$2" in amd64) echo x86_64-unknown-linux-musl ;; arm64) echo aarch64-unknown-linux-musl ;; *) echo "" ;; esac ;;
    just-lsp)
      case "$2" in amd64) echo x86_64-unknown-linux-gnu ;; arm64) echo aarch64-unknown-linux-gnu ;; *) echo "" ;; esac ;;
    *) echo "" ;;
  esac
}
```

- [ ] **Step 2: Verify it sources and resolves a tool**

Run:
```bash
bash -c 'set -eu; . scripts/versions/manifest.sh; tool_meta just; echo "$KIND $METHOD $VERSION_VAR $MEMBER"; tool_arch just amd64'
```
Expected:
```
github tar JUST_VERSION just
x86_64-unknown-linux-musl
```

- [ ] **Step 3: Commit**

```bash
git add scripts/versions/manifest.sh
git commit -m "feat: add tool manifest for binary installs"
```

---

### Task 3: install.sh (shared installer) with offline URL test

**Files:**
- Create: `scripts/versions/install.sh`
- Create: `scripts/versions/test_versions.sh`

- [ ] **Step 1: Write the failing test (URL expansion regression guard)**

`scripts/versions/test_versions.sh`:

```bash
#!/usr/bin/env bash
# Offline tests for the versions tooling. No network required.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
check() { # check <label> <actual> <expected>
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1"; echo "  expected: $3"; echo "  actual:   $2"; fail=1
  fi
}

export VERSIONS_LOCK="$DIR/../../versions.lock"

# --- install.sh --print-url must match the URLs currently in Dockerfile.tooling ---
amd64() { ARCH_OVERRIDE=amd64 bash "$DIR/install.sh" --print-url "$1"; }
arm64() { ARCH_OVERRIDE=arm64 bash "$DIR/install.sh" --print-url "$1"; }

check "git-delta amd64 url" "$(amd64 git-delta)" \
  "https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_amd64.deb"
check "glab arm64 url" "$(arm64 glab)" \
  "https://gitlab.com/gitlab-org/cli/-/releases/v1.100.0/downloads/glab_1.100.0_linux_arm64.deb"
check "just amd64 url" "$(amd64 just)" \
  "https://github.com/casey/just/releases/download/1.36.0/just-1.36.0-x86_64-unknown-linux-musl.tar.gz"
check "just-lsp arm64 url" "$(arm64 just-lsp)" \
  "https://github.com/terror/just-lsp/releases/download/0.3.4/just-lsp-0.3.4-aarch64-unknown-linux-gnu.tar.gz"
check "terraform amd64 url" "$(amd64 terraform)" \
  "https://releases.hashicorp.com/terraform/1.15.3/terraform_1.15.3_linux_amd64.zip"

# --- resolve.sh parses stubbed upstream payloads (see Task 4) ---
if [ -f "$DIR/resolve.sh" ]; then
  out="$(RESOLVE_SELFTEST=1 bash "$DIR/resolve.sh" 2>/dev/null || true)"
  check "resolve git-delta" "$(echo "$out" | grep '^GIT_DELTA_VERSION=')" "GIT_DELTA_VERSION=9.9.9"
  check "resolve glab strips v" "$(echo "$out" | grep '^GLAB_VERSION=')" "GLAB_VERSION=2.0.0"
  check "resolve terraform" "$(echo "$out" | grep '^TERRAFORM_VERSION=')" "TERRAFORM_VERSION=1.99.0"
fi

exit $fail
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash scripts/versions/test_versions.sh`
Expected: FAIL — `install.sh` does not exist yet (`No such file or directory`).

- [ ] **Step 3: Write install.sh**

`scripts/versions/install.sh`:

```bash
#!/usr/bin/env bash
# install.sh <name>            download + install a tool from the manifest at its pinned version
# install.sh --print-url <name>  print the resolved download URL and exit (offline; for tests)
#
# Version comes from versions.lock (override path via VERSIONS_LOCK).
# Arch comes from `dpkg --print-architecture` (override via ARCH_OVERRIDE for tests).
set -euo pipefail

# Resolve this script's real directory even when invoked via a symlink (e.g. /usr/local/bin/install-tool).
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  target="$(readlink "$SOURCE")"
  case "$target" in
    /*) SOURCE="$target" ;;
    *)  SOURCE="$(dirname "$SOURCE")/$target" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

print_url_only=0
if [ "${1:-}" = "--print-url" ]; then print_url_only=1; shift; fi
name="${1:?usage: install.sh [--print-url] <tool-name>}"

LOCK_FILE="${VERSIONS_LOCK:-$SCRIPT_DIR/versions.lock}"
# shellcheck disable=SC1090
. "$LOCK_FILE"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/manifest.sh"

tool_meta "$name"

version="${!VERSION_VAR:-}"
: "${version:?$VERSION_VAR is empty in $LOCK_FILE (set it or run 'just lock')}"

dpkg_arch="${ARCH_OVERRIDE:-$(dpkg --print-architecture)}"
arch="$(tool_arch "$name" "$dpkg_arch")"
[ -n "$arch" ] || { echo "Unsupported architecture '$dpkg_arch' for $name" >&2; exit 1; }

# Expand the template (only ${VERSION} and ${ARCH} are substituted; no eval).
url="${URL_TMPL//\$\{VERSION\}/$version}"
url="${url//\$\{ARCH\}/$arch}"

if [ "$print_url_only" -eq 1 ]; then
  echo "$url"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
file="$tmp/download"

wget -qO "$file" "$url"
[ -s "$file" ] || { echo "Empty download from $url" >&2; exit 1; }

case "$METHOD" in
  deb)
    dpkg -i "$file"
    ;;
  tar)
    mkdir -p "$DEST"
    # shellcheck disable=SC2086
    tar -xzf "$file" -C "$DEST" $MEMBER
    ;;
  zip)
    mkdir -p "$DEST"
    unzip -q "$file" "$MEMBER" -d "$DEST"
    ;;
  *)
    echo "Unknown install method '$METHOD' for $name" >&2; exit 1 ;;
esac

echo "installed $name $version ($arch)"
```

- [ ] **Step 4: Run the test, verify URL checks pass**

Run: `bash scripts/versions/test_versions.sh`
Expected: the five `ok - ... url` lines print; the three `resolve ...` checks are skipped (resolve.sh absent). Exit 0.

- [ ] **Step 5: Lint**

Run: `shellcheck scripts/versions/manifest.sh scripts/versions/install.sh scripts/versions/test_versions.sh`
Expected: no errors (warnings already suppressed via inline `disable` directives).

- [ ] **Step 6: Commit**

```bash
git add scripts/versions/install.sh scripts/versions/test_versions.sh
git commit -m "feat: add install.sh helper with offline URL regression test"
```

---

### Task 4: resolve.sh (`just lock` resolver)

**Files:**
- Create: `scripts/versions/resolve.sh`

- [ ] **Step 1: Write resolve.sh with a self-test stub hook**

The `RESOLVE_SELFTEST=1` branch lets `test_versions.sh` exercise the tag-parsing/prefix-stripping logic offline. The real path uses `curl` + `jq`.

`scripts/versions/resolve.sh`:

```bash
#!/usr/bin/env bash
# resolve.sh [lockpath]   query upstream "latest" for each tool and rewrite versions.lock.
# Manual dev step (`just lock`); never run during image build.
# Requires: curl, jq.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/manifest.sh"
LOCK_FILE="${1:-$SCRIPT_DIR/../../versions.lock}"

# Fetch the latest tag for a tool given KIND/REPO already set by tool_meta.
latest_tag() {
  case "$KIND" in
    github)
      curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | jq -r '.tag_name' ;;
    gitlab)
      local enc="${REPO//\//%2F}"
      curl -fsSL "https://gitlab.com/api/v4/projects/$enc/releases?per_page=1" | jq -r '.[0].tag_name' ;;
    hashicorp)
      curl -fsSL "https://api.releases.hashicorp.com/v1/releases/terraform/latest" | jq -r '.version' ;;
    *)
      echo "Unknown kind '$KIND'" >&2; return 1 ;;
  esac
}

# Offline self-test stub: returns canned tags so test_versions.sh can verify prefix stripping.
if [ "${RESOLVE_SELFTEST:-0}" = "1" ]; then
  latest_tag() {
    case "$KIND" in
      github)    echo "9.9.9" ;;
      gitlab)    echo "v2.0.0" ;;
      hashicorp) echo "1.99.0" ;;
    esac
  }
fi

emit() {
  local t tag ver
  for t in $ALL_TOOLS; do
    tool_meta "$t"
    tag="$(latest_tag)"
    ver="${tag#"$TAG_PREFIX"}"
    printf '%s=%s\n' "$VERSION_VAR" "$ver"
  done
}

if [ "${RESOLVE_SELFTEST:-0}" = "1" ]; then
  emit
  exit 0
fi

command -v jq >/dev/null || { echo "resolve.sh requires jq" >&2; exit 1; }

header='# Pinned versions for binary tools installed in Dockerfile.tooling.
# Single source of truth. Regenerate with `just lock`; edit a line to override.'

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$header" > "$tmp"
emit >> "$tmp"
mv "$tmp" "$LOCK_FILE"
echo "wrote $LOCK_FILE:"
cat "$LOCK_FILE"
```

- [ ] **Step 2: Run the offline self-test branch**

Run: `RESOLVE_SELFTEST=1 bash scripts/versions/resolve.sh`
Expected (order matches `ALL_TOOLS`):
```
GIT_DELTA_VERSION=9.9.9
GLAB_VERSION=2.0.0
JUST_VERSION=9.9.9
JUST_LSP_VERSION=9.9.9
TERRAFORM_VERSION=1.99.0
```
Note `GLAB_VERSION=2.0.0` confirms the `v` prefix was stripped.

- [ ] **Step 3: Run the full offline test suite (now includes resolve checks)**

Run: `bash scripts/versions/test_versions.sh`
Expected: all `ok` lines, including `resolve git-delta`, `resolve glab strips v`, `resolve terraform`. Exit 0.

- [ ] **Step 4: Smoke-test the live resolver into a temp file (network)**

Run: `tmp=$(mktemp); bash scripts/versions/resolve.sh "$tmp"; cat "$tmp"; rm "$tmp"`
Expected: five `*_VERSION=` lines with real current versions (each non-empty, no leading `v`).

- [ ] **Step 5: Lint**

Run: `shellcheck scripts/versions/resolve.sh`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add scripts/versions/resolve.sh scripts/versions/test_versions.sh
git commit -m "feat: add resolve.sh upstream-latest resolver"
```

---

### Task 5: Wire Dockerfile.tooling to the helper

**Files:**
- Modify: `Dockerfile.tooling`

- [ ] **Step 1: COPY the helper + lock near the top of the General developer tooling root section**

In `Dockerfile.tooling`, immediately after `USER root` (currently line 23) and before the GitHub CLI block, insert:

```dockerfile
# Binary-tool installer: shared helper + manifest + pinned versions (versions.lock).
# COPY'd before first use so both the root-context and $USERNAME-context tool installs below
# can call `install-tool <name>`. Bumping versions.lock invalidates layers from here down (intended).
COPY scripts/versions/ /usr/local/share/tool-install/
COPY versions.lock /usr/local/share/tool-install/versions.lock
RUN chmod +x /usr/local/share/tool-install/install.sh \
    && ln -s /usr/local/share/tool-install/install.sh /usr/local/bin/install-tool
```

- [ ] **Step 2: Replace the glab RUN block**

Replace the current glab block (the `ARG GLAB_VERSION` line plus its `RUN set -eu; ... rm "glab_..."` block) with:

```dockerfile
# GitLab CLI (glab). Version pinned in versions.lock.
# https://gitlab.com/gitlab-org/cli/-/releases
RUN install-tool glab
```

- [ ] **Step 3: Replace the git-delta RUN block**

Replace the current git-delta block (`ARG GIT_DELTA_VERSION` + its `RUN ... rm "git-delta_..."`) with:

```dockerfile
# Git Delta: pretty git diffs. Version pinned in versions.lock.
RUN install-tool git-delta
```

- [ ] **Step 4: Replace the just RUN block (user section)**

Replace the current just block (`ARG JUST_VERSION` + its `RUN set -eu; ... tar -xz -C ... just`) with:

```dockerfile
# just CLI. Version pinned in versions.lock.
RUN install-tool just
```

- [ ] **Step 5: Replace the just-lsp RUN block**

Replace the current just-lsp block (`ARG JUST_LSP_VERSION` + its `RUN ... tar -xz -C ... ./just-lsp`) with:

```dockerfile
# just-lsp. Version pinned in versions.lock.
RUN install-tool just-lsp
```

- [ ] **Step 6: Replace the terraform RUN block**

Replace the current terraform block (`ARG TERRAFORM_VERSION` + its `RUN set -eu; ... unzip ...`) with:

```dockerfile
# Terraform. Version pinned in versions.lock.
RUN install-tool terraform
```

- [ ] **Step 7: Sanity-check no stale version ARGs/refs remain**

Run: `grep -nE 'ARG (GIT_DELTA|GLAB|JUST|JUST_LSP|TERRAFORM)_VERSION|releases/download|releases.hashicorp' Dockerfile.tooling || echo "clean"`
Expected: `clean` (all five inline download blocks and their ARGs are gone).

- [ ] **Step 8: Build the tooling image for the host arch**

Run: `just build-tooling` (requires Task 6's Justfile edit; if doing Task 5 standalone, run `docker build --build-arg BASE_IMAGE=ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base:latest -f Dockerfile.tooling -t tooling-test .`)
Expected: build succeeds; the five `install-tool` RUN steps each print `installed <name> <version> (<arch>)`.

- [ ] **Step 9: Verify the binaries inside the image**

Run:
```bash
docker run --rm tooling-test bash -lc 'delta --version && glab --version && just --version && just-lsp --version && terraform version'
```
Expected: each prints its version without error (versions match `versions.lock`).

- [ ] **Step 10: Commit**

```bash
git add Dockerfile.tooling
git commit -m "refactor: install binary tools via shared install-tool helper"
```

---

### Task 6: Justfile — drop version vars/build-args, add lock recipe

**Files:**
- Modify: `Justfile`

- [ ] **Step 1: Remove the five version variable lines**

Delete these lines from the top of `Justfile`:

```
GIT_DELTA_VERSION := "0.18.2"
GLAB_VERSION := env("GLAB_VERSION", "1.100.0")
JUST_VERSION := env("JUST_VERSION", "1.36.0")
JUST_LSP_VERSION := env("JUST_LSP_VERSION", "0.3.4")
TERRAFORM_VERSION := env("TERRAFORM_VERSION", "1.15.3")
```

(Keep `PNPM_COREPACK_VERSION` and `YARN_COREPACK_VERSION` — out of scope.)

- [ ] **Step 2: Remove the five tooling build-args**

In the `build-tooling` recipe, delete these five `--build-arg` lines:

```
        --build-arg GIT_DELTA_VERSION="{{ GIT_DELTA_VERSION }}" \
        --build-arg GLAB_VERSION="{{ GLAB_VERSION }}" \
        --build-arg JUST_VERSION="{{ JUST_VERSION }}" \
        --build-arg JUST_LSP_VERSION="{{ JUST_LSP_VERSION }}" \
        --build-arg TERRAFORM_VERSION="{{ TERRAFORM_VERSION }}" \
```

The recipe keeps `--build-arg BASE_IMAGE=...` and the `--tag`/`--file` lines. `versions.lock` is read from the build context by the helper inside the image, so no build-arg is needed.

- [ ] **Step 3: Add the `lock` recipe**

Add near the build recipes:

```just
# Resolve the latest upstream versions of the binary tools and rewrite versions.lock.
# Manual maintenance step; review the diff and commit. Requires curl + jq.
lock:
    bash scripts/versions/resolve.sh
```

- [ ] **Step 4: Verify Just parses and the recipe is listed**

Run: `just --list | grep -E 'lock|build-tooling'`
Expected: both `lock` and `build-tooling` appear; no parse error.

- [ ] **Step 5: Verify lock is a no-op against current pins (network)**

Run: `just lock && git diff --stat versions.lock`
Expected: `versions.lock` rewritten; if upstream has not advanced past the pinned values, `git diff` shows no change (or only newer versions if upstream moved). Either way the file stays valid env-style.

- [ ] **Step 6: Commit**

```bash
git add Justfile versions.lock
git commit -m "refactor: drive binary tool versions from versions.lock in Justfile + add lock recipe"
```

---

### Task 7: CI workflow — drop tooling version build-args

**Files:**
- Modify: `.github/workflows/docker-devcontainer.yml`

- [ ] **Step 1: Remove the four tooling build-args and the comment block**

In the `build-tooling` job's `Build and push tooling` step, the `build-args:` block currently reads:

```yaml
          build-args: |
            BASE_IMAGE=${{ steps.toolbase.outputs.base }}
            GIT_DELTA_VERSION=${{ vars.GIT_DELTA_VERSION }}
            JUST_VERSION=${{ vars.JUST_VERSION }}
            JUST_LSP_VERSION=${{ vars.JUST_LSP_VERSION }}
            TERRAFORM_VERSION=${{ vars.TERRAFORM_VERSION }}
```

Replace it with just:

```yaml
          build-args: |
            BASE_IMAGE=${{ steps.toolbase.outputs.base }}
```

`versions.lock` is checked out with the repo and read from the build context by the helper inside the image, so no `vars.*` are needed for these tools.

- [ ] **Step 2: Remove the stale "keep aligned" comment block in the base job**

In the `build-base` job's `Build and push base` step, delete the three comment lines referring to keeping variables aligned and to `GIT_DELTA_VERSION and JUST_LSP_VERSION` (currently the comment block immediately above `build-args:` there). The `PNPM_COREPACK_VERSION` / `YARN_COREPACK_VERSION` build-args themselves stay (out of scope).

- [ ] **Step 3: Verify the workflow has no stale tooling-version references**

Run: `grep -nE 'GIT_DELTA_VERSION|JUST_VERSION|JUST_LSP_VERSION|TERRAFORM_VERSION|GLAB_VERSION' .github/workflows/docker-devcontainer.yml || echo "clean"`
Expected: `clean`.

- [ ] **Step 4: Validate YAML parses**

Run: `python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/docker-devcontainer.yml")); print("yaml ok")'`
Expected: `yaml ok`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/docker-devcontainer.yml
git commit -m "ci: read binary tool versions from versions.lock instead of repo vars"
```

---

### Task 8: Full multi-arch build verification

**Files:** none (verification only)

- [ ] **Step 1: Run the offline test suite once more**

Run: `bash scripts/versions/test_versions.sh`
Expected: all `ok`, exit 0.

- [ ] **Step 2: Build tooling for both target arches (matches CI platforms)**

Run:
```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  --build-arg BASE_IMAGE=ghcr.io/hyperfocus1337/coding-agent-sandbox/devcontainer-base:latest \
  -f Dockerfile.tooling -t tooling-multiarch-test .
```
Expected: both platforms build successfully; the five `install-tool` steps run on each.

- [ ] **Step 3: Confirm a forced-empty version fails loudly (guard regression)**

Run:
```bash
bash -c 'set -e; export VERSIONS_LOCK=/dev/null; bash scripts/versions/install.sh --print-url just' ; echo "exit=$?"
```
Expected: non-zero exit with a message naming `JUST_VERSION` empty (the `:?` guard fires). `exit=` shows non-zero.

- [ ] **Step 4: Final commit (if any verification tweaks were needed)**

```bash
git add -A
git commit -m "test: verify lockfile-driven binary tool install across arches" || echo "nothing to commit"
```

---

## Notes for the implementer

- **Cache busting:** `COPY versions.lock` sits high in `Dockerfile.tooling`, so bumping any version rebuilds the tool layers below it. That is intended (a version change must reinstall). Unrelated layers above the COPY (the keyring/apt setup) keep their cache.
- **`$HOME` at build time:** the user-context tools install to `$HOME/.local/bin`; under `USER node` that resolves to `/home/node/.local/bin`, matching the original hardcoded paths.
- **`install-tool` on PATH:** the symlink in `/usr/local/bin` makes the command available to both `USER root` and `USER $USERNAME` sections without re-COPYing.
- **Resolver auth:** `resolve.sh` uses unauthenticated GitHub/GitLab APIs (a handful of calls; well under rate limits). No token needed for `just lock`.
