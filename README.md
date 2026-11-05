# Workbench

One terminal setup for working beside coding agents, on macOS, Linux and Windows: [Herdr](https://herdr.dev) on the desktop, tmux on servers, Helix as the editor, and one set of keys, popups and pickers across all of them.

## What This Project Is

- **Herdr on the desktop.** The multiplexer with an agent sidebar: it shows which Claude Code or Codex pane is working, blocked or done, and conversations come back after a restart. The installer sets it up with the `C-a` prefix, the popups and the theme; see the [Herdr guide](docs/herdr.md).
- **tmux on servers.** The same prefix and popups where Herdr is not an option. `C-a s` installs the config over SSH and, while a remote tmux is in front, your keys act there. tmux is installed on desktops too, for those sessions.
- **Helix as the editor**, configured for reviewing agent-written code: send a selection to the agent, open the `file:line` it mentions, lazygit a key away. The separate [irlm/nvim](https://github.com/irlm/nvim) Neovim config stays available with `--nvim`.
- **Agent workflow.** `C-a w` lists every agent with its state and task, `C-a C-d` reviews what it changed with the diff beside each file and sends a hunk back, `C-a C-g` gives each task its own worktree. Under Herdr the sidebar queues agents by urgency, shows the task each is on, and the size of the uncommitted work per workspace.
- **Popups and pickers** for `lazygit`, `lazydocker`, notes, projects, search, LLM usage and limits, plus the shell prompt and CLI tooling bootstrap.

The repository was `irlm/tmux` until November 2026; the old URLs redirect. The checkout lives in `~/.config/tmux` because tmux reads its config there.

The root README is intentionally lean. Full documentation lives in [`docs/`](docs/README.md).

## Install

Install commands and `dotup` follow **`main`**. Changes pushed to another branch become available through these commands after they are merged into `main`.

### macOS / Linux

```bash
# Desktop: Herdr, tmux, Helix, the tools and the popups
curl -sL https://raw.githubusercontent.com/irlm/workbench/main/install.sh | bash

# Full: also the dev toolchains (Rust, Go, Node, Java, Scala), Docker and the complete shell setup
curl -sL https://raw.githubusercontent.com/irlm/workbench/main/install.sh -o /tmp/install.sh && bash /tmp/install.sh --full

# Server: tmux, Helix and the light tool set (add --herdr for Herdr there too)
curl -sL https://raw.githubusercontent.com/irlm/workbench/main/install.sh | bash -s -- --server
```

Flags: `--no-herdr` for a tmux-only desktop, `--nvim` for Neovim as a second editor, `--agent` names the default. Nothing heavy arrives without `--full`.

### Windows (PowerShell)

Run PowerShell as Administrator:

```powershell
irm https://raw.githubusercontent.com/irlm/workbench/main/install.ps1 | iex
```

Windows gets Herdr, Helix and the tools; `$env:INSTALL_FULL = "1"` first adds the toolchains and Docker Desktop, `INSTALL_HERDR=0` skips Herdr. For tmux itself on Windows, use WSL: `wsl --install`.

If `irm` sits there with no output, PowerShell is waiting on the Windows proxy settings (corporate proxy, "automatically detect settings"); `curl.exe` does not use them:

```powershell
curl.exe -sL https://raw.githubusercontent.com/irlm/workbench/main/install.ps1 -o $env:TEMP\wb-install.ps1
pwsh -ExecutionPolicy Bypass -File $env:TEMP\wb-install.ps1
```

Do not paste the macOS / Linux one-liner into PowerShell: `bash` there is the WSL launcher, so it installs the Linux workbench inside WSL (fine if that is what you want; the script says so on its first lines).

## First Run

1. The installer installs `JetBrainsMono Nerd Font` and points Ghostty or Windows Terminal at it; any other terminal, pick that font in its settings.
2. Start Herdr with `herdr` (on a server: `tmux`, then `C-a I` once for its session plugins).
3. Edit with `hx` (Helix, configured from this repo; `hx --tutor` teaches the keys).
4. Press `C-a C-t` (Ctrl-a, then Ctrl-t) to preview and save a theme; under Herdr, `C-a r` applies it.

## Update an Existing Install

```bash
~/.config/tmux/update.sh --check  # report versions and health; change nothing
~/.config/tmux/update.sh --quick  # update configs and plugins; skip package upgrades
```

`dotup` is the alias for `~/.config/tmux/update.sh`: one run pulls this repo, refreshes Helix, the shell file, the tmux plugins, Herdr and its config, the `gh` extensions and the managed Homebrew tools, then runs the health check. Use it for the full update. The updater reloads running tmux; with managed shell integration, open a new shell for prompt changes. Your theme and personal settings in `~/.config/tmux-user/` persist across updates. See the [installation guide](docs/installation.md#updating) for older shell setups, repair options, and local Git changes.

## Basic Commands and Keys

| Command / Key | What it does |
|---------------|--------------|
| `herdr` | start Herdr, the desktop multiplexer with the agent sidebar |
| `tmux` | start tmux (servers, or a plain session on the desktop) |
| `hx` | open Helix |
| `C-a c` | create a new window (a tab in Herdr) |
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
| `C-a $` | LLM usage and limits for Claude Code, Codex and the others |
| `C-a C-f` | open a `file:line` the pane mentions in Helix |
| `C-a w` | every agent on the machine: state, task, time in that state; Enter jumps, `C-s` prompts |
| `C-a C-d` | review what changed: file list with the diff beside, Enter opens at the change, `C-a` sends it to the agent |
| `C-a C-g` | a worktree per task: pick one or type a branch, in its own workspace or session |
| `C-a C-n` / `C-a C-o` | Herdr: next agent, jump to the agent that just notified |
| `dotup` | update repos, plugins, gh extensions, and CLI tools (on a server: `~/.config/tmux/update.sh`, or the curl one-liner in the [installation guide](docs/installation.md#updating)) |

## Full Documentation

- [Documentation hub](docs/README.md)
- [Installation guide](docs/installation.md)
- [Usage and keybindings](docs/usage.md)
- [Features and project layout](docs/features.md)
- [Herdr](docs/herdr.md)
- [Customization and diagnostics](docs/customization.md)

## Related Repo

- [irlm/nvim](https://github.com/irlm/nvim) for the optional Neovim/LazyVim configuration
