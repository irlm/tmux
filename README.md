# Tmux + Neovim Dev Environment

Cross-platform terminal setup: tmux, neovim (LazyVim), Oh My Posh, Nord theme, full dev toolchain, and modern CLI tools.

## Quick Install

### macOS / Linux

```bash
curl -sL https://raw.githubusercontent.com/irlm/tmux/main/install.sh | bash
# or if curl is not installed:
wget -qO- https://raw.githubusercontent.com/irlm/tmux/main/install.sh | bash
```

### Full Setup (multi-distro Linux + macOS)

```bash
curl -sL https://raw.githubusercontent.com/irlm/tmux/main/install.sh | bash -s -- --full
# or:
wget -qO- https://raw.githubusercontent.com/irlm/tmux/main/install.sh | bash -s -- --full
```

Full setup adds: multi-distro support (Fedora, Arch, openSUSE, WSL), shell config (.zshrc/.bashrc), Nerd Font, zsh plugins, fzf keybindings, WSL clipboard.

### Windows (PowerShell)

> Run PowerShell as **Administrator** (right-click -> Run as administrator).

```powershell
irm https://raw.githubusercontent.com/irlm/tmux/main/install.ps1 | iex
```

This installs via Scoop + winget:

| Category | Packages |
|----------|----------|
| Editor | neovim (LazyVim with LSP for 9 languages) |
| Dev toolchain | Rust (rust-analyzer), Go, Python, Node.js, Java (OpenJDK), Scala (Coursier + Metals) |
| Git | git, lazygit, gh (GitHub CLI) |
| Containers | Docker Desktop, lazydocker |
| CLI tools | fzf, zoxide, bat, btop, fastfetch, oh-my-posh |
| Fonts | JetBrains Mono Nerd Font, MesloLGM Nerd Font |
| Shell | PowerShell profile with oh-my-posh, zoxide, fzf, aliases |

**After install — set terminal font:**
1. Open **Windows Terminal** > Settings > Profiles > Defaults > Appearance
2. Set Font face to **JetBrainsMono Nerd Font** (or **JetBrainsMono NF**)

> tmux doesn't run natively on Windows. For tmux, install WSL: `wsl --install` in an admin PowerShell.

## What You Get

- **tmux** — `C-a` prefix, vim-style panes, popups (lazygit, btop, gh dash), sessionizer
- **neovim** — LazyVim with Nord theme, LSP for 9 languages, telescope, treesitter, tmux navigation
- **Dev toolchain** — Rust (rust-analyzer), Go, Python (pyright, ruff), Node.js, Java (jdtls), Scala (Metals), C/C++ (clangd)
- **Docker** — Docker + Docker Desktop, lazydocker
- **Oh My Posh** — Nord-themed prompt with git status, smart path truncation
- **CLI tools** — fzf, zoxide, bat, eza, lazygit, btop, fastfetch, gh, ripgrep, fd, jq
- **Status bar** — CPU, RAM, network speed, battery (auto-hidden on desktops), git branch
- **Session persistence** — tmux-resurrect + continuum auto-saves/restores sessions

## Post-Install

1. Set your terminal font to a **Nerd Font** (e.g. MesloLGM, JetBrains Mono)
2. Start tmux: `tmux`
3. Install tmux plugins: `C-a I`
4. Open neovim: `nvim` (plugins + LSPs auto-install on first launch)

## Updating

```bash
~/.config/tmux/update.sh
```

Fetches latest changes, updates plugins, reloads config, and checks for missing toolchains.

## Keybindings (C-a prefix)

### Popups

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `g` | lazygit | `n` | quick notes |
| `G` | gh dash | `o` | sessionizer (project switcher) |
| `d` | lazydocker | `?` | cheatsheet |
| `t` | btop | `/` | search pane history |
| `i` | fastfetch | `f` | floating shell |

### Panes

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `\|` | split horizontal | `z` | zoom toggle |
| `-` | split vertical | `x` | kill pane (confirms on last) |
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

### SSH / Nested Tmux

| Key | Action |
|-----|--------|
| `s` | SSH + auto-attach remote tmux (prompts for host) |
| `F12` | Toggle local prefix off/on (pass keys to inner tmux) |

When `F12` is active, status bar shows **REMOTE** in red — all keys go to the inner (remote) tmux. Press `F12` again to switch back.

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
| `C-s` | save session (resurrect) |
| `C-r` | restore session (resurrect) |
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
- **Language support**: Rust, C/C++, Java, TypeScript/JS, JSON, Python, Go, Scala, SQL
- **`<Space>gg`** lazygit from within neovim
- **`<Space>ff`** find files, **`<Space>fg`** live grep
- **`gd`** go to definition, **`Ctrl-o`** jump back
- Minimal lualine (no duplicate info with tmux status bar)

## Files

| File | Description |
|------|-------------|
| `install.sh` | Bootstrap for macOS / Linux (`--full` for multi-distro) |
| `install.ps1` | Bootstrap for Windows (PowerShell) |
| `setup.sh` | Full setup engine (called by `install.sh --full`) |
| `update.sh` | Pull latest, update plugins, check toolchains |
| `tmux.conf` | tmux configuration |
| `nord.omp.json` | Oh My Posh Nord prompt theme |
| `cheatsheet.txt` | keybinding reference (`C-a ?`) |
| `scripts/status_right.sh` | dynamic status bar (cpu/ram/net/battery) |
| `scripts/net_speed.sh` | network speed monitor |
| `scripts/sessionizer.sh` | fzf project switcher |
| `scripts/notes.sh` | quick notes manager |

## Repos

| Repo | What |
|------|------|
| [irlm/tmux](https://github.com/irlm/tmux) | tmux + shell config (this repo) |
| [irlm/nvim](https://github.com/irlm/nvim) | neovim / LazyVim config |
