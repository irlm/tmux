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
- `gh-dash` (installed as a `gh` extension: `gh extension install dlvhdr/gh-dash`)
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
- installs the `gh-dash` GitHub CLI extension that backs the `C-a G` popup (run `gh auth login` once for it to show data)
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

`install.sh` appends its shell settings to the file your shells already read: an existing `~/.zshrc` first, then an existing `~/.zprofile` (common on macOS setups that never had a `.zshrc`), and it only creates `~/.zshrc` when neither exists. It prints which file it chose and backs that file up before touching it. Every block it adds is guarded, so re-running the installer does not duplicate them. `setup.sh --full` is different: it owns the shell config and writes a complete `~/.zshrc` (or `~/.bashrc`) after backing up the old one, leaving any `~/.zprofile` alone.

## Post-Install Checklist

1. Open a new terminal or restart the current one.
2. Set your terminal font to a Nerd Font.
3. Start tmux with `tmux`.
4. Install tmux plugins with `C-a I`.
5. Open Neovim with `nvim` and let the first-run setup finish.
6. If Docker was installed, launch Docker Desktop on macOS or Windows, or re-log on Linux if Docker group membership changed.
7. Run `gh auth login` so the `C-a G` GitHub dashboard popup can load your PRs and issues.

## Updating

Run any of these:

```bash
dotup                 # update everything (alias for ~/.config/tmux/update.sh)
dotcheck              # report only, change nothing
dotup --quick         # repo and plugin updates only, skip package upgrades
dotup --fix           # install anything missing without asking
```

`C-a C-u` runs the same update inside a tmux popup.

That script:

- updates the tmux repo, then re-executes itself if `update.sh` itself changed
- installs TPM if missing, then installs, updates, and cleans tmux plugins
- reloads the tmux config if tmux is running
- updates the Neovim repo and runs Neovim plugin sync
- upgrades the `gh-dash` extension, installing it when missing
- upgrades the Homebrew formulae these installers manage (macOS)
- checks for missing CLI tools and language toolchains, and offers to run `install.sh` to fill the gaps

### When an update reports a problem

| Message | What it means |
|---------|---------------|
| `cannot reach GitHub` | the fetch failed (offline, or credentials the helper could not supply); the update skips that repo and carries on |
| `Blocked by local changes — these plugins could not update` | a Neovim plugin has uncommitted changes, usually a generated file such as `markdown-preview.nvim`'s `app/yarn.lock`. Run the `git -C <path> checkout .` line it prints, then update again |
| `gh-dash missing, installing...` followed by a failure | the GitHub CLI is not authenticated yet — run `gh auth login`, then update again |
| `Toolchains missing: ...` | language toolchains are absent; answer the prompt, or re-run with `dotup --fix` |
| `Toolchains missing: java` or `metals` after installing them | on macOS both live off the default PATH (keg-only `openjdk`, and Coursier's `~/Library/Application Support/Coursier/bin`). The installers add them to the shell config they write — open a new shell, or re-run the installer if your shell config predates it |

Neovim's plugin sync is verbose, so its full transcript goes to `~/.local/share/tmux/update-nvim.log` and only problems are printed.

Homebrew upgrades are limited to the formulae these installers manage, so the rest of your Homebrew setup is left alone.

## Related Repos

- [irlm/tmux](https://github.com/irlm/tmux): tmux config, scripts, and installers
- [irlm/nvim](https://github.com/irlm/nvim): Neovim / LazyVim config
