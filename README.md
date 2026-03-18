# Tmux + Shell Bootstrap

Cross-platform terminal setup with tmux, Oh My Posh, Nord theme, and modern CLI tools.

Works on **macOS**, **Linux** (Ubuntu, Debian, Fedora, RHEL, Arch, Manjaro, openSUSE), **WSL**, and **Windows** (native).

## What you get

- **tmux** with `C-a` prefix, vim-style panes, popups (lazygit, btop, gh dash, fastfetch)
- **Oh My Posh** prompt with Nord theme + git status
- **fzf** for history (`C-r`), files (`C-t`), and directories (`Alt-c`)
- **Modern CLI**: eza (ls), bat (cat), zoxide (cd), ripgrep, fd, jq, tlrc
- **Zsh** with autosuggestions + syntax highlighting (Unix) / **PowerShell** with PSReadLine vi mode (Windows)
- **Nord color scheme** everywhere

## Quick install

### macOS

```bash
# Install Xcode CLI tools (if needed)
xcode-select --install

# Clone and run
git clone https://github.com/irlm/tmux.git ~/.config/tmux
bash ~/.config/tmux/setup.sh
```

### Linux (Ubuntu / Debian / Fedora / Arch / openSUSE)

```bash
# Ensure git is installed
sudo apt install git    # Debian/Ubuntu
sudo dnf install git    # Fedora/RHEL
sudo pacman -S git      # Arch

# Clone and run
git clone https://github.com/irlm/tmux.git ~/.config/tmux
bash ~/.config/tmux/setup.sh
```

The script auto-detects your distro and uses the native package manager (apt/dnf/pacman/zypper).

### WSL (Windows Subsystem for Linux)

```bash
# Same as Linux — the script detects WSL automatically
git clone https://github.com/irlm/tmux.git ~/.config/tmux
bash ~/.config/tmux/setup.sh
```

WSL extras: installs `win32yank` for clipboard and sets `wslview` as browser.
Fonts must be installed on the **Windows side** (the script will show instructions).

### Windows (native — PowerShell + Windows Terminal)

> tmux doesn't run natively on Windows. This setup configures **Windows Terminal**
> with tmux-like keybindings and a matching PowerShell environment.

```powershell
# Allow scripts (run once, as admin)
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# Clone and run
git clone https://github.com/irlm/tmux.git "$env:USERPROFILE\.config\tmux"
& "$env:USERPROFILE\.config\tmux\setup-windows.ps1"
```

**Requirements:** Windows 10/11, [Windows Terminal](https://aka.ms/terminal), [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) (included in Windows 11, install [App Installer](https://apps.microsoft.com/detail/9NBLGGH4NNS1) on Windows 10).

## Post-install steps

### All platforms

1. Set your terminal font to **JetBrains Mono Nerd Font**
2. Restart your terminal

### macOS / Linux / WSL

3. Start tmux: `tmux`
4. Install tmux plugins: `C-a I` (capital I)
5. Open a new shell or `source ~/.zshrc`

### Windows

3. Restart Windows Terminal (keybindings + Nord theme apply automatically)

## Keybindings

### tmux (macOS / Linux / WSL)

Prefix is `C-a` (Ctrl+a). Press prefix, then the key.

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `\|` | Split horizontal | `c` | New window |
| `-` | Split vertical | `,` | Rename window |
| `h j k l` | Navigate panes | `X` | Kill window |
| `H J K L` | Resize panes | `< >` | Reorder windows |
| `x` | Close pane | `N` | New session |
| `z` | Zoom pane | `.` | Rename session |
| `b` | Break pane to window | `S` | Pick session |
| `@` | Join pane | `BkSp` | Last session |

**Popups:**

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `g` | lazygit | `f` | Floating shell |
| `G` | gh dash | `i` | fastfetch |
| `t` | btop | `?` | Cheatsheet |

**Copy mode** (prefix + `[`):

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `v` | Begin selection | `H / L` | Start / end of line |
| `y` | Yank | `/ ?` | Search down / up |
| `C-v` | Block select | `Esc` | Exit |

**Plugins:**

| Key | Action |
|-----|--------|
| `I` | Install plugins |
| `U` | Update plugins |
| `Space` | Thumbs (text hints) |
| `u` | fzf URLs |
| `r` | Reload config |

### Windows Terminal

Uses `Alt` as modifier instead of tmux's `C-a` prefix.

| Windows Terminal | tmux equivalent | Action |
|-----------------|-----------------|--------|
| `Alt+Shift+\` | `C-a \|` | Split horizontal |
| `Alt+-` | `C-a -` | Split vertical |
| `Alt+h/j/k/l` | `C-a h/j/k/l` | Navigate panes |
| `Alt+Shift+H/J/K/L` | `C-a H/J/K/L` | Resize panes |
| `Alt+x` | `C-a x` | Close pane |
| `Alt+z` | `C-a z` | Zoom pane |
| `Alt+c` | `C-a c` | New tab |
| `Alt+Shift+X` | `C-a X` | Close tab |
| `Alt+1-9` | `C-a 1-9` | Switch tabs |
| `Alt+,` | `C-a ,` | Rename tab |
| `Alt+Shift+< >` | `C-a < >` | Reorder tabs |
| `Alt+g` | `C-a g` | lazygit (new tab) |
| `Alt+Shift+G` | `C-a G` | gh dash (new tab) |
| `Alt+t` | `C-a t` | btop (new tab) |
| `Alt+i` | `C-a i` | fastfetch (new tab) |
| `Alt+/` | — | Find/search |
| `Alt+[ / ]` | — | Scroll up/down |

### Shell aliases (all platforms)

| Alias | Command | Alias | Command |
|-------|---------|-------|---------|
| `gs` | `git status` | `ls` | `eza --icons` |
| `gl` | `git log --graph` | `ll` | `eza -la --icons --git` |
| `gp` | `git push` | `cat` | `bat` |
| `gpl` | `git pull` | `z` | `zoxide (smart cd)` |
| `lg` | `lazygit` | `tree` | `eza --tree` |

## Platform support matrix

| Feature | macOS | Linux | WSL | Windows |
|---------|-------|-------|-----|---------|
| tmux | Homebrew | native pkg | native pkg | N/A |
| Window splits | tmux panes | tmux panes | tmux panes | WT panes |
| Oh My Posh | brew | official script | official script | winget |
| Nerd Font | brew cask | auto-download | manual (Windows) | auto-download |
| Clipboard | pbcopy (OSC52) | xclip | win32yank | native |
| Shell | zsh | zsh (auto-set) | zsh (auto-set) | PowerShell |
| Package manager | brew | apt/dnf/pacman/zypper | apt/dnf/pacman | winget |
| fzf integration | brew + shell | pkg + shell | pkg + shell | PSFzf module |

## Files

| File | Description |
|------|-------------|
| `setup.sh` | Bootstrap for macOS, Linux, and WSL |
| `setup-windows.ps1` | Bootstrap for native Windows |
| `tmux.conf` | tmux configuration |
| `nord.omp.json` | Oh My Posh Nord theme |
| `catppuccin.omp.json` | Oh My Posh Catppuccin theme (alternative) |
| `cheatsheet.txt` | tmux keybinding reference (`C-a ?`) |
| `CHANGELOG.md` | Version history |

## Uninstalling

### macOS / Linux / WSL

```bash
rm -rf ~/.config/tmux ~/.tmux/plugins
# Restore backed-up shell config from ~/.config/shell-backup/
```

### Windows

```powershell
Remove-Item "$env:USERPROFILE\.config\tmux" -Recurse
# Restore Windows Terminal settings from the .backup file
# Delete PowerShell profile: Remove-Item $PROFILE
```

## Managing tmux plugins

1. Add plugin to `tmux.conf`: `set -g @plugin 'author/plugin'`
2. Install: `C-a I`
3. Update: `C-a U`
4. Uninstall: remove the line, then `C-a Alt+u`

Plugins are stored in `~/.tmux/plugins/`.
