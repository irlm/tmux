# Tmux + Neovim Dev Environment

Cross-platform terminal setup for a consistent development environment on macOS, Linux, and Windows.

## What This Project Is

This repo is the tmux and terminal side of the setup. It gives you:

- a tmux workflow built around the `C-a` prefix
- helper popups for tools like `lazygit`, `lazydocker`, notes, and project switching
- shell prompt and CLI tooling bootstrap scripts
- integration with the separate [irlm/nvim](https://github.com/irlm/nvim) Neovim config

The root README is intentionally lean. Full documentation lives in [`docs/`](docs/README.md).

## Install

### macOS / Linux

```bash
# Default install
curl -sL https://raw.githubusercontent.com/irlm/tmux/main/install.sh | bash

# Full install
curl -sL https://raw.githubusercontent.com/irlm/tmux/main/install.sh -o /tmp/install.sh && bash /tmp/install.sh --full

# Lightweight server install
curl -sL https://raw.githubusercontent.com/irlm/tmux/main/install.sh | bash -s -- --server
```

### Windows (PowerShell)

Run PowerShell as Administrator:

```powershell
irm https://raw.githubusercontent.com/irlm/tmux/main/install.ps1 | iex
```

For tmux on Windows, use WSL: `wsl --install`

## First Run

1. Set your terminal font to a Nerd Font such as `JetBrainsMono Nerd Font` or `MesloLGM Nerd Font`.
2. Start tmux with `tmux`.
3. Install tmux plugins with `C-a I`.
4. Open Neovim with `nvim` and let plugins/LSPs finish installing on first launch.

## Basic Commands and Keys

| Command / Key | What it does |
|---------------|--------------|
| `tmux` | start tmux |
| `nvim` | open Neovim |
| `C-a c` | create a new tmux window |
| `C-a \|` / `C-a -` | split the current pane |
| `C-a h j k l` | move between panes |
| `C-a g` | open `lazygit` in a popup |
| `C-a o` | open the sessionizer/project switcher |
| `C-a ?` | open the built-in cheatsheet |
| `~/.config/tmux/update.sh` | update tmux, Neovim, and plugins |

## Full Documentation

- [Documentation hub](docs/README.md)
- [Installation guide](docs/installation.md)
- [Usage and keybindings](docs/usage.md)
- [Features and project layout](docs/features.md)

## Related Repo

- [irlm/nvim](https://github.com/irlm/nvim) for the Neovim/LazyVim configuration
