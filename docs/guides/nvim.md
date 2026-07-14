# Neovim config

The Neovim config in [config/nvim/](../../config/nvim/) is a minimal setup for editing inside a container that has no X display or Wayland session. Its one job is to make yank land on the host clipboard.

## The problem

Inside a container there is no local clipboard provider (no `xclip`, `wl-copy`, or `pbcopy` talking to a real display). A normal `y` in Neovim copies into a register that never reaches the host, so pasting into a browser or another app on your machine does not work.

## How it works

The config yanks to the system clipboard over OSC52 escape sequences. Neovim writes the clipboard data as a terminal escape sequence, the terminal emulator sees it and relays the content to the host clipboard. This works across the container boundary because it rides the same terminal stream you are already connected through, so it needs no shared socket or display.

Two settings make this happen in [init.lua](../../config/nvim/init.lua):

- `vim.opt.clipboard = "unnamedplus"` routes the unnamed register through the `+`/`*` clipboard registers, so a plain `y`/`p` uses the system clipboard instead of a Neovim-only register.
- `vim.g.clipboard` registers an OSC52 provider (from the builtin `vim.ui.clipboard.osc52` module) for both copy and paste on the `+` and `*` registers.

## Where it works

Copy works over Docker exec, SSH, and tmux. For tmux you need `set -g set-clipboard on` so tmux passes the escape sequence through to the outer terminal instead of swallowing it.

Paste is best-effort. Many terminals answer an OSC52 write (copy) but refuse an OSC52 read (paste), so paste from the host clipboard may no-op. When it does, use the terminal's own paste (for example Ctrl+Shift+V) instead of `p`.

## Requirements

Neovim 0.10 or newer, since the config relies on the builtin `vim.ui.clipboard.osc52` module.
