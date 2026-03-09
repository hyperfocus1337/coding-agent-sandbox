# !/bin/bash

# Install Emacs without X
apt update
apt install -y emacs-nox

# Launch Emacs once to let it install Magit
emacs --batch -l ~/.emacs.d/init.el
