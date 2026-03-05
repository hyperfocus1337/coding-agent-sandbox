#!/bin/bash

set -e

if ! command -v claude &>/dev/null; then
    echo "ERROR: 'claude' not found in PATH. Check that the Claude Code install placed its binary in a directory on PATH." >&2
    echo "PATH=$PATH" >&2
    exit 1
fi

# Official plugins
# Official marketplace should be already installed (added for debugging)
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin install code-review@claude-plugins-official
claude plugin install commit-commands@claude-plugins-official
claude plugin install feature-dev@claude-plugins-official

# Pyright LSP plugin (waiting to be released)
# https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pyright-lsp
claude plugin install pyright-lsp@claude-plugins-official
npm install -g pyright

# Upstash plugin
claude plugin marketplace add upstash/context7
claude plugin install context7-plugin@context7-marketplace

# Whobson plugin
claude plugin marketplace add wshobson/agents
claude plugin install code-refactoring@claude-code-workflows

# MCP servers
claude mcp add --scope user tessl -- tessl mcp start
claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp
claude mcp add-json github --scope user '{"type":"http","url":"https://api.githubcopilot.com/mcp","headers":{"Authorization":"Bearer YOUR_GITHUB_PAT"}}'
