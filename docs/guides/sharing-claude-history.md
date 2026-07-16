# Preserving Claude Code Conversation History Across Installations

## How Claude Code stores history

Conversation sessions are stored as JSONL files under:

```bash
~/.claude/projects/<encoded-path>/
```

The folder name is the absolute project path with `/` replaced by `-`. For example, `/Users/user/projects/myrepo` becomes `-Users-user-projects-myrepo`.

## Migration steps

### 1. Initialize Claude on the target machine first

Run `claude` on the target machine and complete the auth flow before copying anything. This ensures credentials are created cleanly and won't be overwritten.

### 2. Identify the project folder to migrate

On the source machine:
```bash
ls ~/.claude/projects/
```

Find the folder corresponding to your project. The name reflects its absolute path on the source machine.

### 3. Determine the target path encoding

The folder must match the project's absolute path on the **target** machine. Derive the folder name by replacing every `/` with `-` in the absolute path.

| Source path                           | Target path                                                              |
| ------------------------------------- | ------------------------------------------------------------------------ |
| `/Users/user/.claude/projects/myrepo` | `/home/user/.claude/projects/-workspace-${localWorkspaceFolderBasename}` |

### 4. Copy and rename in one step

When using Docker volumes:

```bash
docker container create --name temp-copy -v coding-agent-sandbox-devcontainer-volume:/data node:25-trixie
docker cp ~/.claude/projects/-Users-user-projects-myrepo/. temp-copy:/data/.claude/projects/-workspace-${localWorkspaceFolderBasename}/
docker rm temp-copy
```

### 5. Optionally copy global settings

```bash
docker cp ~/.claude/settings.json temp-copy:/data/settings.json
```

### 6. Verify

On the target machine, run:

```bash
claude -r
```

Your sessions should now appear in the resume picker.

### Restart again

```bash
docker exec -it -u root coding-agent-sandbox-devcontainer rm -rf /home/user/.claude/projects/-workspace-${localWorkspaceFolderBasename}
```

## What to copy and what not to

| File/folder                   | Copy?         | Notes                                  |
| ----------------------------- | ------------- | -------------------------------------- |
| `~/.claude/projects/<name>/`  | ✅            | Rename to match target path            |
| `~/.claude/settings.json`     | ✅            | Global preferences                     |
| `~/.claude/CLAUDE.md`         | ✅            | Global instructions                    |
| `~/.claude/history.jsonl`     | ⚠️ Optional   | Prompt input recall (up arrow history) |
| `~/.claude/.credentials.json` | ❌            | Re-authenticate instead                |