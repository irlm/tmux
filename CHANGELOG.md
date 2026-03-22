# Changelog

All notable changes to this tmux configuration will be documented in this file.

## [4.5.0] - 2026-03-21

### Added (neovim)
- **Markdown inline rendering**: `render-markdown.nvim` renders headings, bold, code blocks, tables directly in the buffer (`<Space>mr` to toggle)
- **Markdown browser preview**: `markdown-preview.nvim` opens live preview in browser (`<Space>mp` to toggle)

## [4.4.0] - 2026-03-21

### Added
- **Web search popup**: `C-a e` prompts for a query and shows DuckDuckGo results via fzf; `Enter` opens in browser, `Ctrl-W` opens in w3m
- **Search scope picker**: `C-a E` lets you scope search to Wikipedia, GitHub, StackOverflow, or MDN before showing results
- **Ask AI popup**: `C-a a` prompts a question, shows Claude's answer in a popup
- **Man page popup**: `C-a M` opens man pages in a popup
- **Cheat.sh popup**: `C-a C` shows cheat sheets with syntax highlighting
- **tldr popup**: `C-a V` shows simplified command examples
- **Cross-platform browser opener**: Uses `xdg-open` on Linux, `open` on macOS, with w3m fallback
- **Dependencies**: w3m (text browser), websearch scripts (`scripts/websearch.sh`, `scripts/websearch_fetch.py`)

### Changed
- **Cheatsheet**: Reorganized layout, added search & reference section, fixed btop keybindings

## [4.3.0] - 2026-03-20

### Added
- **Full dev toolchain in install scripts**: Node.js, Rust (rust-analyzer), Go, Java, Python, Scala (Coursier + Metals) across all platforms (setup.sh, install.sh, install.ps1)
- **Docker installation**: Docker + Docker Desktop across macOS, Linux, and Windows, auto-starts on macOS
- **Neovim in setup.sh**: Installs neovim with version check (requires 0.10+), clones nvim config
- **Nested tmux (SSH) support**: F12 toggles local prefix off/on for controlling inner remote tmux; status bar shows REMOTE indicator
- **SSH + remote tmux shortcut**: `C-a s` prompts for host, SSHs in, and auto-attaches remote tmux
- **tmux-resurrect + continuum re-enabled**: Auto-saves sessions every 15 min, auto-restores on tmux start
- **Safer pane close**: `C-a x` confirms before killing the last pane in a window
- **Toolchain check in update.sh**: Reports missing language toolchains (node, go, rust, java, python, metals, docker)
- **.gitignore**: Excludes `plugins/` directory

### Fixed
- **LazyVim lua extra removed**: `lazyvim.plugins.extras.lang.lua` was dropped upstream, removed from nvim config
- **Mason ensure_installed**: Replaced black/isort with pyright (ruff handles formatting now)
- **Quieter brew installs**: install.sh skips already-installed packages instead of printing warnings

## [3.1.0] - 2026-03-18

### Added
- **Windows native setup** (`setup-windows.ps1`): Full setup for Windows Terminal + PowerShell
- **Windows Terminal keybindings**: Alt-based shortcuts mirroring tmux C-a bindings
  - `Alt+h/j/k/l` pane navigation, `Alt+Shift+H/J/K/L` resize
  - `Alt+Shift+\` / `Alt+-` splits, `Alt+x` close, `Alt+z` zoom
  - `Alt+g` lazygit, `Alt+t` btop, `Alt+i` fastfetch (as new tabs)
  - `Alt+1-9` tab switching, `Alt+c` new tab
- **Nord color scheme** for Windows Terminal
- **PowerShell profile**: Oh My Posh, PSReadLine vi mode, fzf (PSFzf), zoxide, eza/bat aliases
- **Windows cheatsheet**: `cheatsheet-windows.txt` with keybinding mapping table
- **Nerd Font installer**: Downloads and registers JetBrains Mono for current user on Windows

## [3.0.0] - 2026-03-18

### Added
- **Cross-platform support**: `setup.sh` now works on macOS, Ubuntu/Debian, Fedora/RHEL, Arch/Manjaro, openSUSE, and Windows WSL
- **OS auto-detection**: Detects distro family via `/etc/os-release` with `ID_LIKE` fallback
- **Native package managers**: Uses apt/dnf/pacman/zypper on Linux (no Linuxbrew)
- **GitHub release fallback**: Installs lazygit, tlrc, eza from GitHub releases when not in distro repos
- **Debian binary symlinks**: Auto-creates `fd` -> `fdfind` and `bat` -> `batcat` links
- **Linux Nerd Font installer**: Downloads JetBrains Mono Nerd Font to `~/.local/share/fonts`
- **Oh My Posh on Linux**: Installs via official script to `~/.local/bin`
- **WSL clipboard**: Installs `win32yank.exe` for clipboard integration
- **WSL browser**: Sets `wslview` as default browser inside WSL
- **Auto zsh setup**: Installs zsh and sets it as default shell on Linux
- **GitHub CLI repos**: Adds official gh repos for Debian and Fedora
- **xclip fallback**: Installs xclip for clipboard on Linux (non-WSL)
- **Multi-path fzf sourcing**: `.zshrc` checks all common fzf install locations

### Changed
- **setup.sh**: Refactored from macOS-only to cross-platform architecture with helper functions
- **.zshrc**: Now portable across macOS, Linux, and WSL

### Fixed
- **CPU overhead**: Override nord-tmux forcing `status-interval` from 1s to 5s (reduced script spawns from 6/sec to 6/5sec)
- **Fastfetch popup**: Fixed premature close and restored color output using `less -R`

## [2.1.0] - 2026-03-17

### Added
- **Bootstrap script** (`setup.sh`): One-command setup for fresh macOS machines
- **Oh My Posh**: Nord theme prompt with git status, language versions, single-line minimal style
- **Catppuccin theme**: Alternative OMP theme available at `catppuccin.omp.json`
- **Cheatsheet**: `C-a ?` opens full shortcut reference with 3-column layout
- **Popup: fastfetch** (`C-a i`): System info popup, closes with `q`
- **Popup: btop** (`C-a t`): Replaces htop with better task/process manager
- **Shell tools**: fzf, lazygit, btop, fastfetch, eza, bat, zoxide, tlrc, jq
- **Zsh plugins**: autosuggestions, syntax-highlighting, completions (no framework)
- **fzf Nord colors**: Matching color scheme for fuzzy finder
- **Shell aliases**: Modern CLI replacements (eza, bat, zoxide), git shortcuts
- **Fastfetch greeting**: Compact system info on new terminal (skipped inside tmux)
- **Oh My Zsh migration**: Script detects and backs up existing OMZ installs
- **Nerd Font**: JetBrains Mono Nerd Font auto-installed

### Changed
- `C-a t` now opens btop instead of htop
- Oh My Posh prompt: minimal plain style (no powerline arrows/boxes)
- Path separator uses `›` instead of `/`

## [2.0.0] - 2026-03-17

Major overhaul of the tmux configuration with new keybindings, plugins, and workflow improvements.

### Added
- **Prefix key**: Changed from `C-b` to `C-a` (easier to reach)
- **True color & undercurl**: Full 24-bit color and undercurl support for modern terminals
- **Vi copy mode enhancements**: `v` to select, `y` to yank, `C-v` block select, `H`/`L` start/end of line, `/`/`?` search
- **Pane resizing**: `Shift+H/J/K/L` to resize panes (repeatable)
- **Intuitive splits**: `|` horizontal, `-` vertical (both open in current path)
- **New windows**: `c` opens new window in current path
- **Quick reload**: `C-a r` to reload config
- **Popup terminals**: `C-a g` lazygit, `C-a G` gh dash, `C-a f` floating shell, `C-a t` htop
- **Session management**: `C-a N` new session, `C-a .` rename session, `C-a ,` rename window, `C-a Backspace` toggle last session
- **Window swapping**: `<` / `>` to reorder windows
- **Pane swapping**: `{` / `}` to swap panes, `b` break pane to window, `@` join pane
- **Smart window naming**: Auto-rename windows to current directory name
- **Window tabs styling**: Clean format with bold active indicator
- **Pane borders**: Heavy lines, dim inactive (colour238), blue active (colour4)
- **Activity monitoring**: Highlighted in status bar without message spam
- **System clipboard**: OSC 52 clipboard integration
- **detach-on-destroy off**: Killing a session switches to next instead of detaching
- **escape-time 0**: No delay after pressing Escape (critical for vim/neovim)
- **Status bar colors**: Cyan CPU, green network speed, cleaner date format (`Tue 17 Mar 14:30`)

### Added Plugins
- `tmux-plugins/tmux-fzf` — fuzzy finder for sessions, windows, panes
- `fcsonline/tmux-thumbs` — vimium-like text hints for quick copy (`C-a Space`)

### Removed Plugins
- `tmux-plugins/tmux-open`
- `tmux-plugins/tmux-copycat`
- `tmux-plugins/tmux-prefix-highlight`
- `tmux-plugins/tmux-sessionist`
- `tmux-plugins/tmux-sidebar`
- `tmux-plugins/tmux-online-status`
- `tmux-plugins/tmux-logging`
- `tmux-plugins/tmux-pain-control`

### Changed
- **Plugin config**: Enabled `continuum-restore`, `resurrect-capture-pane-contents`, `resurrect-strategy-nvim`
- **Status interval**: Reduced from 10s to 5s for faster updates
- **Status right length**: Increased from 120 to 140

## [1.0.0] - 2023-07-15

Initial tmux configuration.

### Added
- Mouse support
- Vi mode keys with `h/j/k/l` pane navigation
- Focus events, 100k history limit
- 1-based window and pane indexing
- Auto-renumber windows
- Bottom status bar with session name, CPU, network speed, battery, datetime
- Nord theme with custom status content

### Plugins
- `tmux-plugins/tpm`
- `tmux-plugins/tmux-sensible`
- `christoomey/vim-tmux-navigator`
- `tmux-plugins/tmux-yank`
- `tmux-plugins/tmux-resurrect`
- `tmux-plugins/tmux-continuum`
- `tmux-plugins/tmux-open`
- `tmux-plugins/tmux-copycat`
- `tmux-plugins/tmux-prefix-highlight`
- `tmux-plugins/tmux-sessionist`
- `tmux-plugins/tmux-sidebar`
- `tmux-plugins/tmux-cpu`
- `tmux-plugins/tmux-battery`
- `tmux-plugins/tmux-net-speed`
- `tmux-plugins/tmux-online-status`
- `tmux-plugins/tmux-logging`
- `tmux-plugins/tmux-pain-control`
- `arcticicestudio/nord-tmux`

### Git History
- `f5d783c` Update README.md
- `1a9b4b7` Add config
- `0904961` Update README.md
- `1f3e793` Initial commit
