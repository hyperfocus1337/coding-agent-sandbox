# Sudo password for ad-hoc package installs

The base image does not put `node` in the `sudo` group or set a login password. The image adds `node` to `sudo` and, if BuildKit secret `container_user_password` is provided (`just build` forwards `SUDO_PASSWORD_FILE` when that path exists), sets a disposable login password via `chpasswd`.

## Setting the password

Use a **throwaway** one-line secret only. Prefer a gitignored file (default `config/.sudo-password`), not repeated command-line literals. The build strips CR/LF line endings from that file so Windows-style `CRLF` does not change the password versus what you type.

```bash
printf '%s\n' 'your-dev-only-secret' > config/.sudo-password
just build
```

## Runtime caveat

**The running image must have been built with the secret.** A `prebuild` or `:latest` pull from GHCR only has a password if CI set the `CONTAINER_USER_PASSWORD` secret when that image was built; your local `config/.sudo-password` is not read at runtime. To confirm whether `node` has a password, run `docker exec -u root -it <container-name> passwd -S node` (`P` means a password is set; `NP` / locked means `sudo` auth will always fail until you rebuild with the secret or run `passwd node` as root).

If that file is absent, password-based `sudo` is unavailable until a root-capable step sets one, for example:

```bash
docker exec -u root -it coding-agent-sandbox-devcontainer passwd node
```

## GitHub Actions

For **GitHub Actions** builds, optionally add a repository secret `CONTAINER_USER_PASSWORD` (same one-line throwaway value); the workflow writes it to a BuildKit secret so the image gets an interactive `sudo` password without a `--build-arg`. Leave the secret unset to skip (typical for CI).
