# shellcheck shell=bash
#
# manifest.sh — static download recipe for each binary tool.
#
# Sourced (not executed) by install.sh and resolve.sh. For a given tool:
#   tool_meta <tool>             sets KIND, REPO, TAG_PREFIX, METHOD, URL_TMPL,
#                                VERSION_VAR, DEST, MEMBER.
#   tool_arch <tool> <dpkg-arch> maps the build arch to the vendor arch string
#                                used in the download URL (empty if unsupported).
# URL_TMPL is a literal template; the {VERSION} and {ARCH} placeholders are
# filled in by install.sh. ALL_TOOLS lists every managed tool.

ALL_TOOLS="git-delta glab just just-lsp terraform"

tool_meta() {
  case "$1" in
    git-delta)
      KIND=github; REPO=dandavison/delta; TAG_PREFIX=""; METHOD=deb
      URL_TMPL="https://github.com/dandavison/delta/releases/download/{VERSION}/git-delta_{VERSION}_{ARCH}.deb"
      VERSION_VAR=GIT_DELTA_VERSION; DEST=""; MEMBER="" ;;
    glab)
      KIND=gitlab; REPO=gitlab-org/cli; TAG_PREFIX="v"; METHOD=deb
      URL_TMPL="https://gitlab.com/gitlab-org/cli/-/releases/v{VERSION}/downloads/glab_{VERSION}_linux_{ARCH}.deb"
      VERSION_VAR=GLAB_VERSION; DEST=""; MEMBER="" ;;
    just)
      KIND=github; REPO=casey/just; TAG_PREFIX=""; METHOD=tar
      URL_TMPL="https://github.com/casey/just/releases/download/{VERSION}/just-{VERSION}-{ARCH}.tar.gz"
      VERSION_VAR=JUST_VERSION; DEST="$HOME/.local/bin"; MEMBER="just" ;;
    just-lsp)
      KIND=github; REPO=terror/just-lsp; TAG_PREFIX=""; METHOD=tar
      URL_TMPL="https://github.com/terror/just-lsp/releases/download/{VERSION}/just-lsp-{VERSION}-{ARCH}.tar.gz"
      VERSION_VAR=JUST_LSP_VERSION; DEST="$HOME/.local/bin"; MEMBER="./just-lsp" ;;
    terraform)
      KIND=hashicorp; REPO=""; TAG_PREFIX=""; METHOD=zip
      URL_TMPL="https://releases.hashicorp.com/terraform/{VERSION}/terraform_{VERSION}_linux_{ARCH}.zip"
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
