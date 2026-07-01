#!/bin/bash

set -e

USERNAME=node

# Create repositories directory
mkdir -p /home/$USERNAME/repositories

# Clone personal agent config from GitHub
git clone https://github.com/hyperfocus1337/coding-agent-config.git /home/$USERNAME/repositories/coding-agent-config

# Navigate to coding-agent-config repository
cd /home/$USERNAME/repositories/coding-agent-config

# Run chezmoi to apply the configuration to the home directory
just chezmoi

# Skip installing as Docker mounts the ~/.claude directory from the volume
# Run the install.sh script to install extensions (plugins, skills or mcp servers)
# ./extensions/install.sh