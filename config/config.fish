# Change default editor to vim
set -x VISUAL vim
set -x KUBE_EDITOR vim

# Add local bin directory
fish_add_path "/home/node/.local/bin"

# direnv hook for automatic .envrc loading
direnv hook fish | source

# Add at the end of the file
starship init fish | source