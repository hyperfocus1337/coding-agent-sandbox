# !/bin/bash

# Install Emacs without X
apt-get update
apt-get install -y emacs-nox

# Launch Emacs once to let it install Magit
emacs --batch -l /home/node/.emacs.d/init.el
