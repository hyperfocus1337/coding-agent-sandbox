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

## Why not a fine-grained token?

GHCR doesn't accept them. GitHub's docs are explicit: [Packages "only supports authentication using a personal access token (classic)"](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry), and [fine-grained tokens list package access as unsupported](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens). A fine-grained token just 403s on `docker pull`. (A classic `read:packages` PAT can't be scoped to one repo either — it reads every package the account sees.)

## The `gh auth token` fallback

Used only when `$GHCR_TOKEN` is unset. It drops your **entire** `gh` token into the config as `base64(username:token)` Basic auth. Docker uses it only for registry pulls, but the token itself stays valid against the whole GitHub API — anything your `gh` token can do, this file can do. Prefer `$GHCR_TOKEN`.

The file stores the credential as reversible base64 (**not** encryption); `chmod 600` limits it, but anyone who can read it recovers the token in plaintext. It lives under `config/.watchtower-docker/` and must stay out of version control. Rotate the PAT on its expiration and re-run with `--force`.
