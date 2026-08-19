# apt packages

OS packages split across two layers: `Dockerfile.base` keeps a lean shell/OS baseline, and `Dockerfile.tooling` adds the AI-agent CLI toolkit and other developer utilities. The final `devcontainer-agent` image contains both.

## Baseline (`Dockerfile.base`)

Only what the base's own build steps and the shell need:

| Package            | Provides    | Purpose                                           |
| ------------------ | ----------- | ------------------------------------------------- |
| `less`             |             | pager                                             |
| `procps`           | `ps`, `top` | process inspection                                |
| `sudo`             |             | privilege escalation (see sudo password section)  |
| `fzf`              |             | fuzzy finder                                      |
| `fish`             |             | default interactive shell                         |
| `unzip`            |             | archive extraction                                |
| `ca-certificates`  |             | TLS root certs                                    |
| `curl`             |             | HTTP download (mise/extrepo, vendor installers)   |
| `gnupg` / `gnupg2` | `gpg`       | signature/key handling for apt keyrings           |
| `neovim`           | `nvim`      | default editor (`EDITOR`/`VISUAL`)                |
| `direnv`           |             | per-directory env loading                         |
| `openssh-client`   | `ssh`       | `ssh-keyscan` for the SSH bootstrap; git over SSH |

`yq` and `starship` are also installed in the base image, via mise (not apt).

`git` is deliberately **not** an apt package: Debian trixie caps at 2.47.3. `Dockerfile.tooling` builds it from the official upstream tarball instead, in one self-contained block (build deps, sha256-pinned download, build, man pages, dep purge). The base and node images therefore have no `git`.

That block installs `gettext`, `libcurl4-openssl-dev`, `libexpat1-dev`, `zlib1g-dev`, `libssl-dev` and `libpcre2-dev`, then purges them again in the same layer, so they do not reach the final image. `apt-mark manual` keeps the five runtime libraries git links against, which `--auto-remove` would otherwise take with the headers. Man pages come from the upstream `git-manpages` tarball, so `man git` works.

## Developer + AI-agent tooling (`Dockerfile.tooling`)

Utilities coding agents shell out to plus general dev/network/data tools, moved off the baseline so the base layer stays minimal:

| Package             | Provides                        | Purpose                                           |
| ------------------- | ------------------------------- | ------------------------------------------------- |
| `ripgrep`           | `rg`                            | fast recursive grep; Claude Code's search backend |
| `fd-find`           | `fd` (symlinked from `fdfind`)  | fast file finder                                  |
| `bat`               | `bat` (symlinked from `batcat`) | `cat` with syntax highlight + line numbers        |
| `shellcheck`        |                                 | shell script linter                               |
| `yamllint`          |                                 | YAML linter                                       |
| `universal-ctags`   | `ctags`                         | symbol/tag indexing for code nav                  |
| `patch`             |                                 | apply unified diffs                               |
| `patchutils`        | `filterdiff`, `interdiff`, …    | manipulate patches                                |
| `miller`            | `mlr`                           | CSV/TSV/JSON stream processor                     |
| `csvkit`            | `csvlook`, `csvcut`, …          | CSV toolkit                                       |
| `httpie`            | `http`, `https`                 | friendly HTTP client                              |
| `netcat-openbsd`    | `nc`                            | TCP/UDP socket tool                               |
| `socat`             |                                 | bidirectional socket relay                        |
| `lsof`              |                                 | list open files / ports                           |
| `file`              |                                 | detect file type by content                       |
| `moreutils`         | `sponge`, `ts`, `chronic`, …    | extra Unix utilities                              |
| `ncdu`              |                                 | interactive disk usage browser                    |
| `strace`            |                                 | trace syscalls / signals                          |
| `rsync`             |                                 | fast incremental file sync                        |
| `wget`              |                                 | HTTP download (gh keyring fetch)                  |
| `dnsutils`          | `dig`, `nslookup`               | DNS debugging                                     |
| `jq`                |                                 | JSON processor                                    |
| `tree`              |                                 | directory tree view                               |
| `man-db`            | `man`                           | manual pages                                      |
| `postgresql-client` | `psql`                          | Postgres CLI                                      |
