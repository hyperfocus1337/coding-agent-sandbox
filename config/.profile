# ~/.profile: executed by Bourne-compatible login shells.

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

# Change default editor to vim
export VISUAL=vim
export KUBE_EDITOR=vim

# Add local bin directory
export PATH="/home/node/.local/bin:$PATH"

# direnv hook for automatic .envrc loading
eval "$(direnv hook bash)"

# Add at the end of the file
eval "$(starship init bash)"