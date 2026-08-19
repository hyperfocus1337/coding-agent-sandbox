# EDITOR/VISUAL/KUBE_EDITOR come from the image env (Dockerfile.base).
alias vim nvim

# Disable MCP servers originating from claude.ai
set -x ENABLE_CLAUDEAI_MCP_SERVERS false

# Everything below is interactive-only: scripts and `fish -c` skip it.
status is-interactive; or return

# No "Welcome to fish" banner
set -g fish_greeting ""

# direnv + mise + starship hooks, pre-rendered at image build time (Dockerfile.base)
# so each shell sources one file instead of spawning four init processes.
source /home/user/.config/fish/hooks.fish
