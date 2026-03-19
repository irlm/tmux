# Tmux + Neovim Dev Environment

Cross-platform terminal setup: tmux, neovim (LazyVim), Oh My Posh, Nord theme, and modern CLI tools.

## Quick Install

### macOS / Linux

```bash
curl -sL https://raw.githubusercontent.com/irlm/tmux/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/irlm/tmux/main/install.ps1 | iex
```

> tmux doesn't run natively on Windows. The script sets up neovim, lazygit, fzf, zoxide, and oh-my-posh in PowerShell. For tmux, use WSL.

## What You Get

- **tmux** — `C-a` prefix, vim-style panes, popups (lazygit, btop, gh dash), sessionizer
- **neovim** — LazyVim with Nord theme, LSP, telescope, treesitter, tmux navigation
- **Oh My Posh** — Nord-themed prompt with git status, smart path truncation
- **CLI tools** — fzf, zoxide, bat, lazygit, btop, fastfetch, gh
- **Status bar** — CPU, RAM, network speed, battery (auto-hidden on desktops), git branch

## Post-Install

1. Set your terminal font to a **Nerd Font** (e.g. MesloLGM, JetBrains Mono)
2. Start tmux: `tmux`
3. Install tmux plugins: `C-a I`
4. Open neovim: `nvim` (plugins auto-install on first launch)

## Updating

```bash
~/.config/tmux/update.sh
```

Fetches latest changes, updates plugins, and reloads config.

## Keybindings (C-a prefix)

### Popups

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `g` | lazygit | `n` | quick notes |
| `G` | gh dash | `o` | sessionizer (project switcher) |
| `t` | btop | `?` | cheatsheet |
| `i` | fastfetch | `/` | search pane history |
| `f` | floating shell | | |

### Panes

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `\|` | split horizontal | `z` | zoom toggle |
| `-` | split vertical | `x` | kill pane |
| `h j k l` | navigate | `b` | break to window |
| `H J K L` | resize | `@` | join pane |
| `{ }` | swap panes | `m` | mark pane |
| `q` | show pane numbers | | |

### Windows / Sessions

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `c` | new window | `N` | new session |
| `,` | rename window | `.` | rename session |
| `X` | kill window | `S` | pick session |
| `< >` | reorder windows | `BkSp` | last session |
| `W` | pick window | `Q` | kill all (confirm) |
| `C-n` | auto-rename on | `D` | pick client to detach |
| | | `Y` | sync panes on/off |

### Copy Mode (C-a [)

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `v` | begin selection | `H / L` | start / end of line |
| `y` | yank | `/ ?` | search down / up |
| `C-v` | block select | `Esc` | exit |

### Plugins

| Key | Action |
|-----|--------|
| `I` | install plugins |
| `Space` | thumbs (copy text hints) |
| `u` | fzf URLs |
| `r` | reload config |

### Utilities

| Key | Action |
|-----|--------|
| `T` | clock mode |
| `C-l` | clear pane history |

## Shell Aliases

| Alias | Command | Alias | Command |
|-------|---------|-------|---------|
| `gs` | git status | `gp` | git push |
| `gl` | git log --graph | `gpl` | git pull |
| `lg` | lazygit | `ta` | new tmux session (dir name) |
| `taa` | attach existing session | `z` | zoxide (smart cd) |

## Status Bar

```
↓2K/s ↑1K/s | 8.0% | 77% | 󰁹 95% | main | Wed 19 Mar 15:30
  net speed    cpu    ram   battery  branch     date/time
```

- Battery section auto-hides on desktops (Mac Mini, Linux without battery)
- Network speed padded to fixed width to prevent shifting
- Git branch shown in status-left next to session name

## Neovim (LazyVim)

Separate repo: [irlm/nvim](https://github.com/irlm/nvim)

- **Nord** colorscheme
- **Ctrl+h/j/k/l** seamless tmux ↔ neovim pane navigation
- **`<Space>gg`** lazygit from within neovim
- **`<Space>ff`** find files, **`<Space>fg`** live grep
- Minimal lualine (no duplicate info with tmux status bar)

## Files

| File | Description |
|------|-------------|
| `install.sh` | Bootstrap for macOS / Linux |
| `install.ps1` | Bootstrap for Windows (PowerShell) |
| `update.sh` | Pull latest, update plugins, reload |
| `tmux.conf` | tmux configuration |
| `nord.omp.json` | Oh My Posh Nord prompt theme |
| `cheatsheet.txt` | keybinding reference (`C-a ?`) |
| `scripts/status_right.sh` | dynamic status bar (cpu/ram/net/battery) |
| `scripts/net_speed.sh` | network speed monitor |
| `scripts/sessionizer.sh` | fzf project switcher |

## Repos

| Repo | What |
|------|------|
| [irlm/tmux](https://github.com/irlm/tmux) | tmux + shell config (this repo) |
| [irlm/nvim](https://github.com/irlm/nvim) | neovim / LazyVim config |
