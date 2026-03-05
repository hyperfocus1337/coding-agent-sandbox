#!/bin/bash

set -e

# Check for updates
tessl outdated

# Install latest Tessl tiles
tessl install --yes --verbose --project-dependencies