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

# Install pyright for lsp server
npm install -g pyright

# Pyright LSP plugin (waiting to be released)
# https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pyright-lsp
# Currently waiting on this: https://github.com/anthropics/claude-plugins-official/issues/379
# claude plugin install pyright-lsp@claude-plugins-official

# Replacement marketplace for LSP plugins, since the official one doesn't have any yet
# https://github.com/Piebald-AI/claude-code-lsps/tree/main/pyright
claude plugin marketplace add piebald-ai/claude-code-lsps
claude plugin install pyright@claude-code-lsps

# Upstash plugin
claude plugin marketplace add upstash/context7
claude plugin install context7-plugin@context7-marketplace

# Whobson plugin
claude plugin marketplace add wshobson/agents
claude plugin install code-refactoring@claude-code-workflows

# Ast-grep plugin
# https://github.com/ast-grep/agent-skill
claude plugin marketplace add ast-grep/agent-skill
claude plugin install ast-grep

# MCP servers
claude mcp add --scope user tessl -- tessl mcp start
claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp