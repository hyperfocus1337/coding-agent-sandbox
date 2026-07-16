# Sudo password for ad-hoc package installs

The base image adds `node` to the `sudo` group but bakes in **no** password, so nothing personal ships in the published images. Instead the password is seeded at **runtime**: `entrypoint.sh` (running as root) reads a mounted file and applies it to `node` before dropping to `node` to run the container.

This password is the privilege boundary that protects the container from a rogue agent: the agent runs as `node`, and without the password it cannot `sudo` to root. The plaintext is mounted into `/root` (mode `0700`), so `node` — and the agent — can neither read it nor reset `node`'s password.

## Setting the password

Put a **throwaway** one-line secret in the gitignored default file, then (re)create the container so the entrypoint seeds it:

```bash
printf '%s\n' 'your-dev-only-secret' > config/.sudo-password
just up   # recreates the container; entrypoint applies the password
```

The mount lives in `.devcontainer/docker-compose.override.yml` (see the `.example`):

```yaml
- ../config/.sudo-password:/root/.sudo-password:ro
```

CR/LF is stripped from the file, so a Windows-style `CRLF` save does not change the password versus what you type.

## Checking / skipping

To confirm the password is set: `docker exec -u root -it coding-agent-sandbox-devcontainer passwd -S node` (`P` means set; `NP` / locked means no seed file was mounted). If you never need password `sudo`, omit the mount and run one-off root commands with `docker exec -u root` instead.

## GitHub Actions

Nothing to configure. The password is never baked into the image, so the CI build needs no `CONTAINER_USER_PASSWORD` secret — you can delete that repository secret if it still exists.
