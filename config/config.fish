# Change default editor to vim
set -x VISUAL nvim
set -x KUBE_EDITOR nvim
alias vim nvim

# Add local bin directory
fish_add_path "/home/node/.local/bin"

# direnv hook for automatic .envrc loading
direnv hook fish | source

# Add at the end of the file
starship init fish | source