#!/usr/bin/env bash
# List the Claude sessions running in the container, one line each: where it runs, what
# it is about, and the command that gets back into it.
#
# Usage: list.sh <container> <resume-command>
#
# <resume-command> is prefixed to the session id, so each line ends in a command the
# caller's own users can paste: `just resume-session` from a recipe, `cas claude resume`
# from cas.
#
# No session running prints nothing: a caller that asks before it kills the container
# has to tell "nothing is running" from "could not ask", and gets that from empty output
# against a non-zero exit. A caller that wants a message for the empty case adds it.
#
# `claude agents --json` is Claude's own session index (pid, cwd, sessionId, name,
# status), so this needs no process scanning and no guessing at how transcript paths are
# encoded. It has no Codex counterpart, so a running Codex session is not listed.
#
# Run from the repository root via: just sessions
set -euo pipefail

usage="usage: list.sh <container> <resume-command>"
container="${1?$usage}"
resume="${2?$usage}"

sessions="$(docker exec -u user "$container" claude agents --json 2>/dev/null)" || {
    echo "sessions: could not list the Claude sessions in $container" >&2
    exit 1
}

# --- One line per session ---

# What `/resume` shows for a session: its first prompt, cut to 50 characters so a
# five-session list stays one line each.
#
# ~/.claude/history.jsonl holds one record per submitted prompt, with the text as
# `display` and the session it belongs to. So the first record for an id is that
# session's first prompt, and nothing has to be filtered out of the transcript: caveats,
# slash-command markers and tool results never reach this file.
#
# Prints nothing for a session that has no prompt yet, or when the file cannot be read.
first_prompt() {
    docker exec -u user "$container" sh -c "grep -m1 -F $1 ~/.claude/history.jsonl 2>/dev/null" |
        jq -r '.display | split("\n")[0] // empty' | cut -c1-50
}

while IFS=$'\t' read -r id project name status; do
    # The name from Claude comes first: it is short, and it is the same string
    # `claude agents` shows. It is only a slug of the directory unless Claude has named
    # the session itself, so "chezmoi-5a" and "chezmoi-7c" tell two sessions in one
    # project apart without saying what either is about. The first prompt says that, so
    # it is added when there is one.
    about="$name, $status"
    # The pipeline in first_prompt fails when the grep finds nothing, which is a session
    # without a prompt, not an error
    prompt="$(first_prompt "$id" || true)"
    if [[ -n "$prompt" ]]; then
        about="$about, \"$prompt\""
    fi
    # Resuming by id ignores the cwd, so the printed command needs no project. It also
    # works for a session in a subdirectory, or in a cwd outside /workspaces.
    echo "$project ($about): $resume $id"
done < <(jq -r '.[] | [.sessionId, (.cwd | ltrimstr("/workspaces/")), .name, .status] | @tsv' <<<"$sessions")