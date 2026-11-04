# Tmux + Neovim Dev Environment

Cross-platform terminal setup for a consistent development environment on macOS, Linux, and Windows.

## What This Project Is

This repo is the tmux and terminal side of the setup. It gives you:

- a tmux workflow built around the `C-a` prefix
- helper popups for tools like `lazygit`, `lazydocker`, notes, and project switching
- the same keys on your servers: `C-a s` installs the config over SSH and, while a remote tmux is in front, your bindings act there
- shell prompt and CLI tooling bootstrap scripts
- integration with the separate [irlm/nvim](https://github.com/irlm/nvim) Neovim config
- the same keys, popups and theme in [Herdr](docs/herdr.md), the multiplexer that shows which coding agent needs you

The root README is intentionally lean. Full documentation lives in [`docs/`](docs/README.md).

## Install

Install commands and `dotup` follow **`main`**. Changes pushed to another branch become available through these commands after they are merged into `main`.

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
5. Press `C-a C-t` (Ctrl-a, then Ctrl-t) to preview and save a theme.

## Update an Existing Install

```bash
~/.config/tmux/update.sh --check  # report versions and health; change nothing
~/.config/tmux/update.sh --quick  # update configs and plugins; skip package upgrades
```

Use `dotup` or `~/.config/tmux/update.sh` for the full update, including managed Homebrew tools. The updater reloads running tmux; with managed shell integration, open a new shell for prompt changes. Your theme and personal settings in `~/.config/tmux-user/` persist across updates. See the [installation guide](docs/installation.md#updating) for older shell setups, repair options, and local Git changes.

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
| `C-a F` | search commands and see missing dependencies |
| `C-a C-t` | choose and preview Nord, Catppuccin, or High contrast |
| `C-a ?` | open the built-in cheatsheet |
| `C-a s` / `C-a P` | SSH to a server (new window / split pane), set it up if needed, attach its tmux |
| `F12` | hand the keys to the remote tmux, or take them back |
| `C-a C-u` | update everything in a popup |
| `C-a $` | LLM usage and limits for Claude Code and Codex |
| `herdr` | the same setup in Herdr, with the agent sidebar (`install.sh --herdr`; Windows: `INSTALL_HERDR=1` with `install.ps1`) |
| `dotup` | update repos, plugins, gh extensions, and CLI tools (on a server: `~/.config/tmux/update.sh`, or the curl one-liner in the [installation guide](docs/installation.md#updating)) |

## Full Documentation

- [Documentation hub](docs/README.md)
- [Installation guide](docs/installation.md)
- [Usage and keybindings](docs/usage.md)
- [Features and project layout](docs/features.md)
- [Customization and diagnostics](docs/customization.md)
- [Herdr](docs/herdr.md)

## Related Repo

- [irlm/nvim](https://github.com/irlm/nvim) for the Neovim/LazyVim configuration
