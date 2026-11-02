# Installation Guide

## Release source

The public install commands below download **`main`**, and the updater pulls `origin main`. A commit pushed to a feature branch is available for review but is not yet distributed by these commands. Merge it into `main` after checks pass before rolling it out to other machines. Changing only the branch in the install script URL is insufficient: bootstrap assets and fresh config clones also use `main`.

Deploy live previews through committed Git states. Copying files directly into
`~/.config/tmux` leaves local changes that can block the next update; keep the
installed checkout clean and put personal settings in `~/.config/tmux-user/local.conf`.

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

- tmux, Neovim and lazygit without a full desktop-style dev bootstrap
- a lightweight shell prompt instead of oh-my-posh
- no Docker installation
- no heavy LSP/toolchain expectations

`update.sh` recognises a server install (by the `~/.config/nvim/.server` marker) and checks for that smaller tool set only; `--fix` re-runs the installer in server mode.

You rarely need to run this by hand: `C-a s` from a workstation that has this config offers to run it on any server that does not (see [usage: SSH and Remote Servers](usage.md#ssh-and-remote-servers)). Once installed, the server's tmux announces itself to the tmux you connect from, so your local keys act on the server.

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

All Unix install modes and the Windows installer stage a new clone before replacing custom configs. Existing configs move to a sibling `.backup.*` directory after the clone succeeds. Clone failures preserve the existing config in place.

Shell integration uses the selected Bash or Zsh shell and preserves personal rc files. The installer adds a managed include after making a backup. Full setup sources its fuller defaults from separate managed shell files. Set `TMUX_TARGET_SHELL` to explicitly choose Bash or Zsh. See [Customization and diagnostics](customization.md) for local overrides and profile options.

## Post-Install Checklist

1. Open a new terminal or restart the current one.
2. Set your terminal font to a Nerd Font.
3. Start tmux with `tmux`.
4. Install tmux plugins with `C-a I`.
5. Open Neovim with `nvim` and let the first-run setup finish.
6. If Docker was installed, launch Docker Desktop on macOS or Windows, or re-log on Linux if Docker group membership changed.
7. Run `gh auth login` so the `C-a G` GitHub dashboard popup can load your PRs and issues.
8. Press `C-a C-t` (Ctrl-a, then Ctrl-t) to preview and save a theme. Reopen lazygit with `C-a g` to see it; open a new shell for the updated prompt.
9. Run `~/.config/tmux/scripts/doctor.sh` to check the installed tools, tmux config, and plugins.

## Updating

For an existing managed installation, use the updater; reinstalling is normally unnecessary:

| Where you are | Command |
|---------------|---------|
| A shell on the machine, alias set up | `dotup` |
| A shell on the machine, no alias (servers, bash) | `~/.config/tmux/update.sh` |
| Inside tmux | `C-a C-u` (same update, in a popup) |
| From another machine, over SSH | `ssh host '~/.config/tmux/update.sh'` |
| Anywhere, straight from GitHub | `curl -sL https://raw.githubusercontent.com/irlm/tmux/main/update.sh \| bash` |

Flags go on the end of any form (`bash -s -- --fix` for the curl one):

```bash
--check    report only, change nothing        (dotcheck is an alias for this)
--quick    repo and plugin updates only, skip package upgrades
--fix      install anything missing without asking
```

For a routine config/plugin update without package upgrades:

```bash
~/.config/tmux/update.sh --check
~/.config/tmux/update.sh --quick
```

Use `dotup` (without `--quick`) when you also want managed Homebrew package upgrades. On Linux, system package upgrades remain the responsibility of your distro's package manager. The updater reloads running tmux; with managed shell integration, open a new shell for prompt changes. Your selected theme and personal settings under `~/.config/tmux-user/` persist across updates.

The `dotup` and `dotcheck` aliases exist only where the installer wrote the shell config; server-mode installs now include the managed aliases too. A machine that does not have the config at all needs the install one-liner, or `C-a s` from a machine that does — not this.

The script pulls the repo first and, if `update.sh` itself changed, re-executes the freshly pulled copy in the same run. The curl form hands over to the installed copy after the pull too. This lets an older install continue with the new updater immediately. Local edits that conflict with incoming files, diverged Git history, missing tools, and network failures can still require repair before an update completes. The updater preserves custom edits and reports failures instead of resetting files. If Neovim's only local change is the generated `lazy-lock.json`, it is backed up in that repository's Git stash before pulling; both staged and working versions remain recoverable with `git -C ~/.config/nvim stash list`.

What the script does:

- updates the tmux repo, then continues with the newest installed `update.sh`
- updates the Neovim repo while preserving local changes, including lock files
- installs TPM if missing, then installs, updates and cleans tmux plugins
- reloads tmux when running and syncs Neovim plugins, including in `--quick` mode
- upgrades GitHub extensions and the managed Homebrew terminal tools
- checks required capabilities and reports each failed component with a nonzero exit status

Full component transcripts are in `~/.local/share/tmux/update-logs/`. A failed pull requires resolving the local Git state in that repository. A missing `gh-dash` extension may require `gh auth login`. For a missing required tool, run `dotup --fix`; for config or plugin problems, follow the exact repair printed by the health check. Language toolchains and Docker remain optional workstation extras.

Homebrew upgrades are limited to the terminal formulae in `tools.tsv`. See [Customization and diagnostics](customization.md) for profiles, personal settings and diagnostic coverage.

### Older shell setups

The updater refreshes the repository and tmux, but does not rewrite personal shell files. If an older installation still initializes its prompt directly from `nord.omp.json`, enable the managed shell integration once after updating:

```bash
bash -c 'source "$HOME/.config/tmux/scripts/install-lib.sh"; install_shell_integration desktop'
```

Use `desktop` for the default installer, `full` for a full install, or `server` for a lightweight server. This backs up the personal rc file before adding an include, writes the managed shell file under `~/.config/tmux-user/`, and installs no packages. Open a new terminal afterward. See [shell integration behavior](customization.md#installer-behavior) for Bash/Zsh selection and full-mode defaults.

## Related Repos

- [irlm/tmux](https://github.com/irlm/tmux): tmux config, scripts, and installers
- [irlm/nvim](https://github.com/irlm/nvim): Neovim / LazyVim config

Update failures now return a nonzero exit status and link to component logs. Local Neovim lock changes are preserved. `--quick` also updates Neovim plugins. See [Customization and diagnostics](customization.md#health-checks-and-updates) for the diagnostic commands and their limits.
