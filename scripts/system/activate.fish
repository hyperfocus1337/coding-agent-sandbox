#!/usr/bin/env fish

# Determine project and venv paths via devcontainer-injected env var
set -l venv_dir $WORKSPACE_FOLDER/devcontainer/.venv

# If direnv is available and .envrc exists, authorize for this project without changing directories
if type -q direnv; and test -f "$WORKSPACE_FOLDER/.envrc"
    direnv allow $WORKSPACE_FOLDER
    echo "[activate.fish] Authorized .envrc for $WORKSPACE_FOLDER" >&2
end

if not test -d "$venv_dir"
    echo "[activate.fish] No .venv found at $venv_dir – skipping activation." >&2
    return 0
end

if test -f "$venv_dir/bin/activate.fish"
    source "$venv_dir/bin/activate.fish"
    echo "[activate.fish] Activated venv at $venv_dir" >&2
else
    echo "[activate.fish] $venv_dir/bin/activate.fish not found – cannot activate venv." >&2
end

