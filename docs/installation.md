# Installation Guide

## Install Modes

| Mode | Best for | Entry point | Notes |
|------|----------|-------------|-------|
| Default | quick workstation setup on macOS or Debian/Ubuntu-style Linux | `install.sh` | installs the core environment, clones tmux + Neovim configs, and sets up a full local dev machine |
| Full (`--full`) | broader Linux distro support and a more complete shell setup | `install.sh --full` | delegates to `setup.sh` for multi-distro support, shell config, extra polish, and WSL-aware behavior |
| Server (`--server`) | remote hosts, minimal systems, or lightweight personal boxes | `install.sh --server` | keeps tmux + Neovim light, skips Docker and oh-my-posh, and avoids heavy language-server setup |
| Windows | PowerShell workstation setup | `install.ps1` | installs Neovim, CLI tools, fonts, and Docker Desktop; for tmux itself, use WSL |

## macOS / Linux

### Default install

```bash
curl -sL https://raw.githubusercontent.com/irlm/tmux/main/install.sh | bash
```

Use this when you want the fastest path to a working local setup. On macOS it uses Homebrew. On Linux it is aimed at apt-based systems.

### Full install

```bash
curl -sL https://raw.githubusercontent.com/irlm/tmux/main/install.sh -o /tmp/install.sh && bash /tmp/install.sh --full
```

Use this when you want broader distro coverage and more opinionated shell setup. The full installer supports:

- macOS
- Ubuntu / Debian family
- Fedora / RHEL family
- Arch / Manjaro family
- openSUSE
- WSL-aware Linux setup

### Server install

```bash
curl -sL https://raw.githubusercontent.com/irlm/tmux/main/install.sh | bash -s -- --server
```

Use this when you want:

- tmux and Neovim without a full desktop-style dev bootstrap
- a lightweight shell prompt instead of oh-my-posh
- no Docker installation
- no heavy LSP/toolchain expectations

## Windows

Run PowerShell as Administrator:

```powershell
irm https://raw.githubusercontent.com/irlm/tmux/main/install.ps1 | iex
```

The Windows installer uses Scoop plus winget to set up:

- Neovim
- `lazygit`, `lazydocker`, `gh`, `fzf`, `zoxide`, `bat`, `btop`, `fastfetch`, `oh-my-posh`
- Rust, Go, Python, Node.js, Java, and Scala tooling
- Docker Desktop
- Nerd Fonts
- PowerShell profile aliases and integrations

tmux does not run natively as part of this Windows flow. For tmux usage, install WSL:

```powershell
wsl --install
```

## What Gets Installed

### Default

The default installer is the quick workstation path. It:

- installs core terminal tools (including `w3m` for terminal web search)
- installs or upgrades Neovim when needed
- installs development toolchains for Neovim extras
- installs Docker when missing
- clones `~/.config/tmux` and `~/.config/nvim`
- installs tmux plugins

### Full

The full installer is the most complete path. It adds:

- broader Linux distro support
- more complete shell integration
- additional CLI tooling and package-manager-specific handling
- WSL-aware setup steps

### Server

Server mode keeps things intentionally lean. It:

- installs tmux, Neovim, and a smaller CLI set
- uses a lightweight shell prompt from this repo
- creates `~/.config/nvim/.server` so Neovim stays lighter
- skips Docker, fonts, and oh-my-posh

## Existing Configs and Backups

The installers clone this repo into `~/.config/tmux` and the Neovim repo into `~/.config/nvim`.

If the installer finds an existing config that is not already one of these repos, it may prompt to back it up first. The default backup location is under `~/.config/dotfiles-backup/`.

## Post-Install Checklist

1. Open a new terminal or restart the current one.
2. Set your terminal font to a Nerd Font.
3. Start tmux with `tmux`.
4. Install tmux plugins with `C-a I`.
5. Open Neovim with `nvim` and let the first-run setup finish.
6. If Docker was installed, launch Docker Desktop on macOS or Windows, or re-log on Linux if Docker group membership changed.

## Updating

Run:

```bash
~/.config/tmux/update.sh
```

That script:

- updates the tmux repo
- updates tmux plugins
- reloads the tmux config if tmux is running
- updates the Neovim repo
- runs Neovim plugin sync
- checks for missing language toolchains

## Related Repos

- [irlm/tmux](https://github.com/irlm/tmux): tmux config, scripts, and installers
- [irlm/nvim](https://github.com/irlm/nvim): Neovim / LazyVim config
