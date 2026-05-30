-- Minimal Neovim config for use inside a container (no X display / Wayland).
-- Yank to the system clipboard over OSC52 escape sequences, which the terminal
-- emulator relays to the host clipboard. Works over Docker exec, SSH, and tmux
-- (with `set -g set-clipboard on`). Requires Neovim 0.10+ for the builtin module.

-- Route the unnamed register through the `+`/`*` clipboard registers so a plain
-- `y`/`p` uses the system clipboard.
vim.opt.clipboard = "unnamedplus"

local osc52 = require("vim.ui.clipboard.osc52")
vim.g.clipboard = {
  name = "OSC52",
  copy = {
    ["+"] = osc52.copy("+"),
    ["*"] = osc52.copy("*"),
  },
  paste = {
    -- Paste from the host clipboard is best-effort: many terminals do not
    -- answer an OSC52 read. Use the terminal's own paste (e.g. Ctrl+Shift+V)
    -- if these no-op.
    ["+"] = osc52.paste("+"),
    ["*"] = osc52.paste("*"),
  },
}
