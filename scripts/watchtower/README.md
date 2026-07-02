# Watchtower GHCR auth (`sync-ghcr-auth.sh`)

Writes `config/.watchtower-docker/config.json` so the Watchtower container can pull private images from `ghcr.io`. Watchtower runs in its own container and can't read the host Docker credential store (macOS `credsStore: osxkeychain` is unavailable there), so it needs its own **inline** credential file.

## Create the token

You need a **classic PAT with `read:packages`** — GHCR does not accept fine-grained tokens (see below). Create one at [github.com/settings/tokens](https://github.com/settings/tokens) → **Generate new token (classic)**:

| Field          | Value                                                                                |
|----------------|--------------------------------------------------------------------------------------|
| **Note**       | Something identifiable, e.g. `watchtower-coding-agent-sandbox-ghcr-pull`.            |
| **Expiration** | A finite window (e.g. 90 days) so it rotates.                                        |
| **Scopes**     | Tick **only `read:packages`**. Nothing else — no `repo`, `write:`/`delete:packages`. |

Copy the value (`ghp_…`, shown once). For a **private org** package, the org may need to permit classic PATs (**Org → Settings → Personal access tokens**) and grant your account read on the package.

## Store the token (`.envrc`)

Keep the PAT out of your shell history. The repo-root `.envrc` is gitignored — put the secret there and let [direnv](https://direnv.net/) export it:

```bash
cp .envrc.example .envrc     # paste your PAT into .envrc
direnv allow
```

```bash
# .envrc
export GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxx
# export GHCR_USER=your-machine-account   # optional; any non-empty value works
```

No direnv? Source it manually: `set -a; . ./.envrc; set +a`.

## Sync

```bash
just sync-watchtower-ghcr-auth          # writes config.json from $GHCR_TOKEN
just sync-watchtower-ghcr-auth --force  # rewrite (e.g. after rotating the PAT)
```

Idempotent: skips if `config.json` already has `ghcr.io` auth (`--force` overrides). Credential order:

1. **`$GHCR_TOKEN`** (preferred) — your `read:packages` PAT.
2. **`gh auth token`** (fallback, when `$GHCR_TOKEN` is unset) — warns, because it embeds your full-scope `gh` token (see below).

## Verify the token is read-only

Three checks confirm the credential Watchtower uses is a read-only pull token and nothing more.

**1. Check the PAT's scopes (definitive).** Ask GitHub which scopes the token carries; a read-only pull token lists exactly `read:packages` and nothing else:

```bash
curl -sI -H "Authorization: token $GHCR_TOKEN" https://api.github.com | grep -i x-oauth-scopes
# x-oauth-scopes: read:packages
```

Extra scopes (`repo`, `write:packages`, `delete:packages`) or a missing header mean the token is broader than it should be — regenerate it with only `read:packages`.

**2. Check that this is the token baked into the config Watchtower reads.** The container loads `config/.watchtower-docker/config.json`; decode the stored `ghcr.io` credential and confirm the token half matches your PAT (not a `gho_…`/`ghp_…` full-scope `gh` token from the fallback):

```bash
jq -r '.auths["ghcr.io"].auth' config/.watchtower-docker/config.json | base64 -d; echo
# <username>:ghp_xxxxxxxx   (-D instead of -d on macOS)
```

If the token differs from `$GHCR_TOKEN`, you synced via the `gh auth token` fallback — set `$GHCR_TOKEN` and re-run `just sync-watchtower-ghcr-auth --force`.

**3. Check the container can't modify that file.** `docker-compose.yml` mounts the config `:ro`, so even the running container cannot alter or widen the credential:

```bash
docker inspect coding-agent-sandbox-watchtower \
  --format '{{range .Mounts}}{{.Destination}} {{if .RW}}rw{{else}}ro{{end}}{{"\n"}}{{end}}'
# /config ro
```

Optional behavioral proof: a `read:packages` token pulls but 403s on any push. After `docker login ghcr.io` with the token, a `docker push` to the registry returns `denied`.

## Why not a fine-grained token?

GHCR doesn't accept them. GitHub's docs are explicit: [Packages "only supports authentication using a personal access token (classic)"](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry), and [fine-grained tokens list package access as unsupported](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens). A fine-grained token just 403s on `docker pull`. (A classic `read:packages` PAT can't be scoped to one repo either — it reads every package the account sees.)

## The `gh auth token` fallback

Used only when `$GHCR_TOKEN` is unset. It drops your **entire** `gh` token into the config as `base64(username:token)` Basic auth. Docker uses it only for registry pulls, but the token itself stays valid against the whole GitHub API — anything your `gh` token can do, this file can do. Prefer `$GHCR_TOKEN`.

The file stores the credential as reversible base64 (**not** encryption); `chmod 600` limits it, but anyone who can read it recovers the token in plaintext. It lives under `config/.watchtower-docker/` and must stay out of version control. Rotate the PAT on its expiration and re-run with `--force`.
