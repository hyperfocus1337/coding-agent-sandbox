# ~/.profile: executed by Bourne-compatible login shells.

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

# Add local bin directory
export PATH="/home/user/.local/bin:$PATH"

# Both hooks are guarded: a login shell that cannot see the tool should stay quiet
# rather than print "command not found" on every exec. PATH itself is restored by
# /etc/profile.d/00-image-path.sh, since /etc/profile resets it before this file runs.

# direnv hook for automatic .envrc loading
command -v direnv >/dev/null && eval "$(direnv hook bash)"

# Add at the end of the file
command -v starship >/dev/null && eval "$(starship init bash)"