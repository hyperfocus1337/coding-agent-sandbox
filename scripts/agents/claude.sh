#!/bin/bash

set -e

USERNAME=node

# Create repositories directory
mkdir -p /home/$USERNAME/repositories

# Clone personal config from GitHub
git clone https://github.com/hyperfocus1337/claude-marketplace.git /home/$USERNAME/repositories/claude-marketplace

# Navigate to integration script
cd /home/$USERNAME/repositories/claude-marketplace/scripts

# Run integration script to symlink commands, skills and CLAUDE.md to ~/.claude
REPO=/home/$USERNAME/repositories/claude-marketplace ./integration/symlink.sh

# Skip installing as Docker mounts the ~/.claude directory from the volume
# Run the install.sh script to install plugins and MCP servers
# ./plugins/install.sh