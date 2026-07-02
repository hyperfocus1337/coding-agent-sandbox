# Change default editor to vim
set -x VISUAL nvim
set -x KUBE_EDITOR nvim
alias vim nvim

# Disable MCP servers originating from claude.ai
set -x ENABLE_CLAUDEAI_MCP_SERVERS false

# Add local bin directory
fish_add_path "/home/node/.local/bin"

# direnv hook for automatic .envrc loading
direnv hook fish | source

# mise: activate so runtime `mise use` and env/tool switching work interactively.
# Baked-in tools already resolve via the shims dir on PATH; this adds the hook.
mise activate fish | source

# Add at the end of the file
starship init fish | source