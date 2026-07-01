# Watchtower GHCR auth (`sync-ghcr-auth.sh`)

Writes `config/.watchtower-docker/config.json` so the Watchtower container can pull private images from `ghcr.io`. Run via `just sync-watchtower-ghcr-auth`.

Watchtower runs inside its own container and cannot read the host Docker credential store (macOS `credsStore: osxkeychain` is unavailable there), so it needs an **inline** credential file of its own.

## Creating the least-privilege token by hand

Start here. You create a scoped PAT once in the GitHub web UI, then feed it to the script via `$GHCR_TOKEN`. It **must be a classic PAT with `read:packages`** — GHCR does not accept fine-grained tokens (see [Why not a fine-grained token?](#why-not-a-fine-grained-token) below). Steps:

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)**, or open [github.com/settings/tokens](https://github.com/settings/tokens) directly.
2. Click **Generate new token → Generate new token (classic)**. Re-authenticate if prompted.
3. Fill in the fields:

   | Field          | Value                                                                                                                            |
   |----------------|----------------------------------------------------------------------------------------------------------------------------------|
   | **Note**       | Something identifiable, e.g. `watchtower-coding-agent-sandbox-ghcr-pull`.                                                        |
   | **Expiration** | A finite window (e.g. 90 days) so it rotates.                                                                                    |
   | **Scopes**     | Tick **only `read:packages`**. Leave everything else unchecked (do **not** tick `repo`, `write:packages`, or `delete:packages`). |

4. Click **Generate token** and copy the value (`ghp_…`) — it is shown only once.
5. Store it in a gitignored `.envrc` (see [Storing the token](#storing-the-token-envrc) below), then run `just sync-watchtower-ghcr-auth --force`.

If the image lives in a **private org** package, confirm the org allows the PAT: **Org → Settings → Personal access tokens** may need to permit classic PATs, and the package's own **Package settings → Manage Actions/repository access** must grant your account read access.

## Why not a fine-grained token?

Because GHCR does not accept them. GitHub's own docs are explicit: [GitHub Packages "only supports authentication using a personal access token (classic)"](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry), and the [fine-grained token limitations](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) list package access as unsupported (on the roadmap, not shipped). A fine-grained token, however tightly scoped, just gets a 403 on `docker pull` from `ghcr.io`. So it cannot be used here regardless of how you would like to scope it.

## Restricting pulls to only this repository's images

A classic `read:packages` token cannot be scoped to a single repository either — it can read **every** package your account has access to. To genuinely limit the credential to only `coding-agent-sandbox` images, don't scope the token, scope the **account** it belongs to:

1. Create a dedicated machine account (a throwaway GitHub user used only for pulls).
2. On the package itself — **Package → Settings → Manage access → Invite team or member** — grant that account the **Read** role, and nothing else. It can now see only this one package.
3. Sign in as that account and create a classic PAT with **only `read:packages`** (steps above).
4. Feed it to the script via `$GHCR_TOKEN`.

The PAT's scope is still account-wide in theory, but the account can *see* only this package, so the token can pull nothing else. That is the practical least-privilege setup for a single-repo pull credential.

**GitHub App alternative:** a GitHub App installed on only this repo, with **Packages: Read**, issues installation tokens that are genuinely repo-scoped. But those tokens **expire hourly**, so the script (which writes a static `config.json`) would need to mint a fresh one on every run instead. Heavier; only worth it if a machine account is not acceptable.

## Storing the token (`.envrc`)

Keep the PAT out of your shell history and command line. The repo root `.envrc` is gitignored — put the secret there and let [direnv](https://direnv.net/) export it when you enter the directory:

```bash
cp .envrc.example .envrc     # then edit .envrc and paste your PAT
direnv allow                 # loads it into the environment
```

`.envrc` contents:

```bash
export GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxx
# export GHCR_USER=your-machine-account   # optional
```

With that loaded, just run `just sync-watchtower-ghcr-auth` — no secret on the command line. After rotating the PAT, update `.envrc`, `direnv allow` again, and re-run with `--force`.

No direnv? Source it manually instead: `set -a; . ./.envrc; set +a` before running the sync.

## Usage

The script picks its credential in this order:

1. **`$GHCR_TOKEN`** (preferred, least privilege) — a `read:packages`-only PAT, exported from your gitignored `.envrc` (see above). Optionally set `$GHCR_USER`; ghcr.io accepts any non-empty username for PAT auth. This is the recommended path:

```bash
just sync-watchtower-ghcr-auth
```

2. **`gh auth token`** (fallback) — used only when `$GHCR_TOKEN` is unset. Emits a warning because it embeds your full-scope `gh` token (see below).

The script is **idempotent**: if `config.json` already contains a `ghcr.io` auth entry it skips and exits. Pass `--force` to rewrite (for example after rotating the token):

```bash
just sync-watchtower-ghcr-auth --force # or: bash scripts/watchtower/sync-ghcr-auth.sh --force
```

## Why the script can't mint the narrow token for you

There is no way to create a scoped token from the CLI. `gh auth token` only returns the broad OAuth token gh already holds; fine-grained PATs have no creation API (web UI only), and the classic-PAT creation API was removed in 2020. So the least-privilege path requires you to create the `read:packages` PAT once by hand, then hand it to the script via `$GHCR_TOKEN`.

## What privilege Watchtower actually gains

With the **fallback** (`gh auth token`) path, the script does **not** mint a narrow token. It reads your existing GitHub CLI token and drops it verbatim into the config as HTTP Basic auth:

```
base64("<your-gh-username>:<your-full-gh-oauth-token>")
```

Consequences of the fallback path:

- **What it uses:** only `read:packages`, to pull private GHCR images. That is Watchtower's entire job. The script warns (but does not block) if your token lacks that scope, since pulls will 403 without it.
- **What it actually holds:** your _whole_ `gh` token, carrying every scope the CLI was granted. A default `gh auth login` (web) grants `repo`, `read:org`, `gist`, and `workflow`; `read:packages` is added by the `gh auth refresh -s read:packages` the script nags for. Docker only exercises the token for registry auth, but the token itself remains valid against the full GitHub API. Anything your `gh` token can do, this file can do.
- **What it cannot do:** push or delete images, unless your `gh` token already has `write:packages` (not requested here).

## Storage and exposure

The credential is stored as reversible base64 (encoding, **not** encryption). The script sets `chmod 600` on the file, but anyone who can read it recovers your live `gh` token in plaintext. The file is under `config/.watchtower-docker/` and must stay out of version control.

## Reducing the blast radius

The fallback (`gh auth token`) path exists for convenience, not because Watchtower needs that much power. Using `$GHCR_TOKEN` above grants only what it uses: pulling images. Rotate the PAT on its expiration schedule and re-run the sync with `--force` to refresh the file after rotation.
