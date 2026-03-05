# Change default editor to vim
set -x VISUAL vim
set -x KUBE_EDITOR vim

# Add local bin directory
fish_add_path "/home/node/.local/bin"

# direnv hook for automatic .envrc loading
direnv hook fish | source

# Source rust
source "$HOME/.cargo/env.fish"

# Activate the virtual environment
source /home/node/scripts/system/activate.fish

# Add at the end of the file
starship init fish | source