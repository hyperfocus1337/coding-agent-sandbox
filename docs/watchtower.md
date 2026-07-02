# Watchtower (auto-updates from GHCR)

The compose stack includes Watchtower for labeled containers. Private GHCR images need a **Watchtower-only** Docker config (macOS `credsStore: osxkeychain` does not work inside the Watchtower container). See [.devcontainer/README.md](../.devcontainer/README.md#ghcr-authentication-private-packages) for details.

```bash
just sync-watchtower-ghcr-auth   # once per machine / after token rotation
just watchtower-auth-check
just up
just update                      # one-shot pull + recreate now
```

| Recipe                      | Purpose                                                            |
|-----------------------------|--------------------------------------------------------------------|
| `sync-watchtower-ghcr-auth` | Write `config/.watchtower-docker/config.json` from `gh auth token` |
| `watchtower-auth-check`     | Fail fast if that file is missing                                  |
| `restart-watchtower`        | Reload auth after sync                                             |
| `update`                    | One-shot Watchtower with `--debug` (see `.devcontainer/README.md`) |
