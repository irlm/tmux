# Changelog

All notable changes to this tmux configuration will be documented in this file.

## [Unreleased]

### Themes

- `C-a C-t` offers Herdr's eight other dark themes beside Nord, Catppuccin and High contrast: Tokyo Night, Dracula, Gruvbox, One Dark, Solarized Dark, Kanagawa, Rose Pine and Vesper, with the colours of Herdr 0.9.5. Under Herdr the pick selects Herdr's theme of that name as it ships; tmux, lazygit, fzf and the prompt get the same colours, the ones under 4.5:1 on a selected row lightened (none in Tokyo Night and Vesper, all in Solarized). Herdr's light themes and `terminal` remain in its own picker.
- Fixed: under Herdr, a second `C-a C-t` pick kept the previous theme. The renderer took the theme it found installed (Catppuccin, after a switch to Nord) for one picked in Herdr's settings and recorded it as `herdr_theme`. Rendered files now carry the name they were written with, in a comment above `[theme]`, and only a different name counts as Herdr's pick; the picker also tells the renderer the pick is its own, which covers files rendered before this. Same change in `herdr-config.ps1`.

### Install modes

- The default install is the workbench only: Herdr, tmux, Helix, the tools, popups and agent keys, the shell integration and the font. The language toolchains (Rust, Go, Node, Java, Scala) and Docker moved under `--full`, which already carried the complete shell setup; `--agent` names the default. On Windows, `$env:INSTALL_FULL = "1"` before the one-liner does the same. A default run says where the rest went. Nothing is removed from machines that already have them.
- `--full` had fallen behind the default: it cloned the repository under its old name, installed no Helix config, no Herdr, no `delta`/`difftastic` on Linux, and always installed Neovim. It now does everything the default does and honours `--nvim` and `--no-herdr`. `--server --herdr` never reached the Herdr step; it does now. `tests/test_install_modes.py` pins what each mode must and must not do.

### Editor

- `C-a C-v` chooses the editor: Helix, Neovim or Vim, whichever are installed, with the default marked. Enter opens the pick in the pane's folder this once, `C-a` makes it the default for this machine on both hosts (`@editor`, kept as `editor=` in `options.env`) and opens it. `C-a v`, `C-a C-f`, the `C-a C-d` review and the notes all open that editor; before, each read `$EDITOR` with a different fallback and a change needed a tmux restart.

### Agents

- `C-a C-b` goes back to the agent you last prompted or jumped to: from `C-a w`, Helix `- a` or the `C-a C-d` review, under Herdr and tmux. It says so when that agent is no longer running.
- `C-a w` under Herdr follows the sidebar's order (each agent under its workspace, or by urgency with `herdr_agent_sort=priority`) instead of always queuing by urgency, and its preview opens with how the agent's context grew (`Context 197k · +47k in the last hour · from 60k at 20:10`). The event hook journals the context size with every state change for that.
- The Herdr sidebar lists agents under their workspace again, the order you work in, so the list is the map of where you were. Queuing by urgency (blocked, done, working) is the opt-in now: `herdr_agent_sort=priority` in `options.env`.
- The agents picker is Herdr's `C-a w` only, with the context size beside each agent. Under tmux `C-a w` is tmux's own window tree again, as before the picker existed; the registry row is Herdr-only, so tmux neither binds the key nor lists the picker in its palette, and a running server gets the default back on reload.
- The Herdr sidebar shows, beside each Claude Code agent, the context its next turn re-reads (`ctx 240k`), read from the session's transcript by the event hook at no cost and painted past `ctx_warn_k` (default 100k tokens).
- Fixed: on Windows that figure never appeared for most sessions. Python there decodes a pipe as cp1252, which has no character for some bytes of UTF-8 text (the end of a closing curly quote is enough), so the transcript reader stopped with an error the hook did not show. It reads bytes now, which also covers a tail that starts inside a character on any platform.
- Fixed: the same hook lost the pane on Windows whenever Herdr's answer held a byte cp1252 has no character for, and the pane title is in that answer: the first frame of the spinner Claude Code shows there while it works is enough. The context figure was not updated for that state change, and the uncommitted-work line only when the event itself named the folder. Herdr's JSON is read as bytes now, and the path goes back to the shell as UTF-8.
- Fixed: the other popups had the same fault on Windows. The agents picker (`C-a w`) could not write its state icons (`◐ ▲ ✔ ○`) to the list at all, and send-to-agent, the project picker, the worktree picker and pane navigation read Herdr's answers as cp1252. `scripts/lib.sh` now runs Python in UTF-8 mode (`PYTHONUTF8=1`) for every script, and the theme picker sets it itself. The Windows CI job checks it through Git Bash.
- The LLM usage card (`C-a $`) on Windows: `install.ps1` installs the `windows-curses` package, which gives Windows Python the `curses` module the card is drawn with, so the popup is the same card as on macOS and Linux (Esc or `q` closes, Tab switches, `r` refreshes) instead of a plain report in `less` that Esc did not close. Where the package has no build for the installed Python, or curses cannot draw on the terminal, the plain report stays and any key closes it when it fits the popup.
- `C-a` in the `C-a C-g` worktree picker opens the worktree and starts a fresh agent in it (`worktree_agent`, default `claude`): one session per task, in one step.
- `install.sh --router` (Windows `INSTALL_ROUTER=1`) installs the [model-router](https://github.com/irlm/model-router) plugin for Claude Code. Opt-in.

- `C-a $` says how to get the live limits when `quota-axi` is missing (`npm install -g quota-axi`); the installers install it where `npm` exists.
- Helix `-d` shows the diff of the file being edited in a split beside it, `-D` the whole repository's, both highlighted as diffs (`scripts/filediff.sh`).
- `C-a v` opens Helix (`$EDITOR`) in the pane's folder, in a pane beside it, under tmux and Herdr.

- `C-a w` lists every coding agent on the machine (state, workspace, task title, time in that state, directory) with the pane beside it: Enter jumps to it, `C-r` reads its last 400 lines, `C-s` sends it a prompt, `C-d` reviews its changes. Under tmux the rows are the panes running `claude` or `codex`.
- `C-a C-d` reviews what changed in the repository behind the pane: one row per changed file with the diff beside it through `delta`, or `difftastic` (a new managed desktop tool, syntax-aware) after `C-d`. Enter opens the file in `$EDITOR` at its first changed line and returns to the list; `C-a` sends that file's diff into the agent's input; `C-w` shows the whole diff; `C-y` copies the path; `C-g` opens lazygit.
- `C-a C-g` gives a task its own worktree: pick an existing one or type a branch name; tmux opens a session, Herdr a workspace grouped under the current one; both keep checkouts in `~/.herdr/worktrees/<repo>/<branch>` (`worktree_dir`).
- Herdr's sidebar queues agents by urgency (blocked, done, working; `herdr_agent_sort=spaces` restores grouping), shows the task under each Claude Code and Codex row, labels agent panes in their borders, and shows the size of the uncommitted work under each workspace (`3 files +40 -12`). The `irlm.workbench` plugin now runs `scripts/agent-events.sh` on every agent state change, which journals it and reports that token; nothing polls.
- The installers, `dotup` and `dotcheck` require Herdr 0.9.5: an older binary is updated before the config is rendered, instead of rejecting the file and leaving Herdr on `ctrl+b`. The renderer says when an attached Herdr still holds its previous keys.
- `install.ps1` is ASCII without a byte-order mark: `irm | iex` on PowerShell 7 handed the mark to `iex` as the first character of the first command, so the one-liner never started and only printed a "not recognized" error. The Windows test guards it. The installer's own downloads also retry without the Windows proxy and through `curl.exe`.
- The installers, Windows included, place Herdr's own agent skill in `~/.claude/skills/herdr` so Claude Code running inside Herdr can coordinate helper agents.
- The Herdr renderer relinks the plugin when Herdr has it registered from another directory, and the theme test no longer touches the real Herdr (it had linked the live plugin from a temporary folder).

### Herdr by default

- Desktop installs on macOS, Linux and Windows install and configure Herdr without a flag; `--no-herdr` (Windows `INSTALL_HERDR=0`) skips it, and `--server --herdr` adds it to a server. The README and docs lead with Herdr on the desktop and tmux on servers.

### Name

- The repository is `irlm/workbench`. GitHub redirects the old `irlm/tmux` URLs, the updater and installers accept checkouts made under either name, and the checkout stays in `~/.config/tmux` because tmux reads its config there. Generated files now say `irlm/workbench`; the older marker is still recognised.

### Plugins

- The CPU reading in the status line is measured by `scripts/status_right.sh` itself (the busy share of `/proc/stat` between samples on Linux, the processes' `%cpu` over the core count on macOS). It had kept calling the removed tmux-cpu plugin and silently vanished once the plugin folder was cleaned; the busy-process name beside it never appeared either, because the threshold compared against `39%` instead of `39`.
- Seven tmux plugins are gone, replaced by this repo's own lines: copy mode copies through `scripts/clipboard.sh` (tmux-yank), `ctrl+hjkl` navigation is in `tmux.conf` and still hands the key to Neovim (vim-tmux-navigator), `C-a Space` and `C-a u` run `scripts/pick.sh` under tmux as well as Herdr (tmux-thumbs, which needed a Rust build, and the URL binding that had no plugin behind it), and the unused tmux-sensible, tmux-cpu, tmux-fzf and nord-tmux. Only tpm, tmux-resurrect and tmux-continuum remain; `dotup` removes the rest.

### Editor

- Helix is the editor every installer sets up, configured from `helix/config.toml` for reviewing beside coding agents: `-a` sends the selection or line into the agent's input, `-f` opens a `file:line` the pane mentions, `-g` opens lazygit, `-r` reloads files an agent changed, `]c` `[c` walk the changes. The shell integration points `EDITOR` at `hx`; `C-a !` shows a Helix cheatsheet.
- Neovim and the irlm/nvim config are optional: `install.sh --nvim` or `INSTALL_NVIM=1` on Windows; an existing checkout keeps being updated. Its compiler and tree-sitter tool are installed only with it (`nvim` scope in `tools.tsv`).
- `C-a C-f` in tmux and Herdr picks any existing `file:line` from the pane and opens it in `$EDITOR`; `scripts/agent-send.sh` pipes text into the first Claude or Codex pane of the workspace.
- lazygit shows diffs through `delta` (syntax colours, line numbers, Nord) when it is installed; `delta` is a managed desktop tool.

### Herdr

- Render a Herdr configuration from the tmux key layout and the action registry: `C-a` prefix, `hjkl`, `|` and `-` splits, every popup under its tmux key, the chosen theme, and the status readings in the tab bar. `install.sh --herdr`, `update.sh` and `doctor.sh` install, refresh and check it; personal settings live in `~/.config/tmux-user/options.env` and `herdr.toml`.
- Share the scripts between the two multiplexers: a backend switch in the library, Herdr branches for pane history, the project switcher (one workspace per project), prompts and ssh, and a `hosts` column in `actions.tsv` and `help.tsv` so each host's reference lists only its keys.
- Add `ctrl+hjkl` navigation that enters Neovim when it runs in the pane (paired with the irlm/nvim `herdr` branch), text and URL pickers over `herdr pane read`, a generated `irlm.workbench` plugin.
- Add `C-a $`: tokens by day and by model for Claude Code and Codex from their transcripts, with live limit windows from quota-axi.
- Map the saved theme onto Herdr's tokens, replacing its dim status colour with the palette's text colour so the tab bar reads like the tmux status line.
- Add `--part net|cpu|ram|battery|holiday` to the status renderer and `herdr_status_colors=on` to emit one coloured tab bar entry per reading, for a Herdr whose entries accept a colour (patch proposed upstream; stock Herdr keeps the single entry with icons).
- Windows: `scripts\herdr-config.ps1` renders the same Herdr config natively, with the popups through Git Bash or WSL; `install.ps1` runs it and installs Herdr with `INSTALL_HERDR=1`.
- Windows installer, verified on a clean Windows 11 VM: pin winget to its own source, install Scoop from an elevated shell, add the java bucket, treat the language toolchains as optional, answer the PowerShell Gallery prompts, save the scripts with a byte-order mark for Windows PowerShell, keep Bash-side files LF in a CRLF checkout, and run the installer from `C-a C-u`.
- Fix the shared Herdr wrapper calling itself by name outside Herdr, which crashed every scripted Herdr call on any system without `HERDR_BIN_PATH` set.
- Keep a theme picked in Herdr's own settings until the next `C-a C-t`, raising only its status token to that theme's text colour; `C-a C-t` re-renders Herdr and takes precedence again.

### Installed update recovery

- Back up a generated Neovim lockfile-only change in Git stash before pulling, preserving staged and working versions while allowing plugin updates to proceed. Keep custom edits under normal Git protection and leave read-only checks untouched.
- Skip Neovim plugin synchronization when its repository update or lockfile backup fails.

### Help popup

- Use the pager's exit status for the `F` handoff so it opens the command palette on Linux without waiting for an extra Return key.
- Pressing `F` in the help popup now opens the command palette, as its hint says. It used to switch `less` into follow mode and show "Waiting for data..." until interrupted. Older `less` versions without lesskey support drop the hint instead.
- Keep the pager's terminal on stderr, so the help no longer sits in "Waiting for data" when it fits on one screen, and escape `:` in the footer, which `less` read as a prompt directive and cut the text short.
- Pad the help to the popup height. A file shorter than the screen made `less` draw it at the bottom, turn the rows above into `~` after `G`, and answer `b`, `k` and Up with a beep, so the title seemed impossible to bring back to the top.

### Installer

- Windows: install gcc and the tree-sitter CLI through Scoop so Neovim can compile its treesitter parsers.
- Install JetBrains Mono Nerd Font in the default install on macOS and Linux (Windows already did), set it as Ghostty's and Windows Terminal's font when they have none, and have the doctor report a missing font: the status icons depend on it.

### Status bar

- Name the process behind a busy CPU reading, above `@cpu_process_threshold` percent (default 30), in both the tmux line and Herdr's tab bar. One `ps` per five-second sample, only while busy.

- Report macOS memory the way Activity Monitor and btop do (app memory plus wired and compressed pages). The previous `memory_pressure` reading treated file cache and inactive pages as free and showed 7% while btop showed 45%.

### Lower idle cost

- Read network counters with `netstat -n` on macOS; without it each status refresh waited about five seconds on reverse DNS, so the status cache never hit and a `netstat` was always running.
- Look the special-day motif up once per day instead of starting Python on every status sample.
- Run the remote-mode check on window renames only while remote mode is on; every command renamed the window and spawned a shell plus several tmux calls for nothing.

### Special day ASCII art

- Spread letter and year fireworks across the sky alongside ordinary bursts, then gather them quickly into the final word. Shorten these shows to three seconds while preserving the frame-rate and canvas limits.

- Launch letters and digits as individual fireworks whose sparks settle into the complete word or year near the finale; hold the finished composition in place.

- Reveal U S A inside July 4 fireworks and the celebration year inside New Year fireworks; use the upcoming year on New Year's Eve and preserve date context in previews and automatic greetings.

- Show one dismissible greeting per local special day, with fireworks for New Year's Day, July 4 and New Year's Eve; include holiday motifs beside the date on wide terminals.
- Add `C-a A` and **Special day art** in the command palette to choose and replay celebrations, with static previews and controls for automatic greetings and motion.
- Add rocket trails, drifting sparks, flying bats, falling snow, floating hearts, clover sparkles and a turkey strut. Cap each animation at four seconds and 12 fps, redraw changed rows only, and sleep without polling after playback. Press `r` to replay.
- Vary arrangements on replay; mix round, willow and heart-shaped fireworks, a floating ghost and a shooting star. Browse holidays with `n` and `p` inside the existing popup without launching another player.

### Theme selection and readable colors

- Add C-a C-t theme selection with previews, based on Nord, Catppuccin Macchiato and a Nord-based high-contrast palette. Save the choice outside the checkout.
- Share colors across tmux, pane palettes where supported, popups, help, fzf and Oh My Posh prompts in new shells.
- Use a lazygit appearance overlay and process-local diff colors while preserving its existing configuration and global Git settings. Brighten Nord red from 2.5:1 to 5.0:1 against the selected-row surface.
- Verify palette contrast, persistence, config merging and actual lazygit rendering in isolated terminal tests.

### Responsive help layout

- Replace the stacked action list and fixed-width cheatsheet with one grouped reference sized to the actual popup interior.
- Use one, two or three columns with aligned key fields, wrapped descriptions, and space between groups. Keep tool-specific references below the main shortcuts and retain pager search/scrolling.

### Workflow reliability and usability

- Prevent duplicate notes and installer replacement from destroying existing content; stage clones and retain backups on every platform.
- Pass prompt text and paths as literal data; retain AI errors and page successful answers.
- Include live sessions, recent projects, configured roots and Git worktrees in project selection; use canonical project identities.
- Report failed update components and exit nonzero; preserve local lock changes; include Neovim plugins in quick updates.
- Scope SSH status to sessions, share SSH discovery, cache status/battery samples, and use private atomic network caches.
- Share tool requirements between checks, Homebrew/Scoop install paths and popup hints; install the Windows PSFzf module before binding it.
- Preserve shell rc files and prompt hooks, select the actual Bash/Zsh target, and support user-owned local overrides and compact/ASCII profiles.
- Add C-a F command search, generated action help, responsive popups, environment diagnostics, regression tests and Unix/Windows CI.
- Start tmux offline without automatically cloning TPM; remove redundant battery/network plugins.

## [4.6.0] - 2026-09-22

### Added
- **Second status line for ssh**: while the active pane holds an ssh (or mosh, autossh, ...) session, a line under the status bar shows `SSH host as user:port`, parsed from the running command. `scripts/status_ssh.sh` had existed since 4.4 but was never wired in; it now runs as a silent toggle from `status-right` (a hidden line can never run its own `#()` commands, so the switch has to live on a line that is always drawn) and as the renderer in `status-format[1]`
- **`C-a P`**: the `C-a s` connect-and-bootstrap flow in a pane split beside the current one. The remote marker it sets is now a pane option rather than a window option, so the local pane of a split keeps the local prefix
- **Server bootstrap over SSH**: `C-a s` now checks the host first and, when this config is not there yet, offers to install it — it copies this machine's own `install.sh` to the server and runs it with `--server`, so both ends run the same version. The check, the install, and the attach share one SSH connection, so you authenticate once
- **Automatic remote mode**: whenever the pane in front is showing a remote tmux, the local prefix switches off so `C-a` and every other binding act on the server, and switches back when you move away, detach, or the connection ends. It does not matter how you connected: a server running this config announces its tmux through the terminal title (`remote.conf`, sourced only under SSH), so an `ssh` typed by hand, `mosh`, and jump hosts are picked up the same way as a `C-a s` window
- **Remote detection does not trust the title alone**: it also requires a remote client program in front (`ssh`, `mosh`, ...; extend with `@remote_clients`) and a full-screen display, wipes leftover markers from a remote tmux that died with its server, and re-checks itself on every status refresh while remote mode is on — so a stale title cannot capture a local `vim`, and a dropped connection cannot leave the prefix off at a local shell
- **`F12` is now an override**, sticky for the window you are in: the way out of a remote window, and the way in for a server that does not run this config
- **Server prompts reset the terminal title** at a bare SSH shell, so a remote tmux that exited uncleanly cannot leave its marker behind
- **Docs**: the usage guide's SSH section is rewritten around the workflow — connecting (`C-a s` or by hand, windows and split panes alike), getting out (`F12` then `C-a n` / `C-a l`), what the status bar means, how detection works, servers without the config, keeping servers current

### Fixed
- **`C-a g` did nothing on a server**: two causes. Server mode never installed lazygit — it now does (one static binary). And the tmux server's PATH lacked `~/.local/bin`, where server mode puts `bat`, `fd`, `rg`, `zoxide` and `tldr`, so no popup could find them either; `scripts/tmux-path.sh` now runs at config load and adds the per-user tool directories (plus Homebrew, the JDK and Coursier) to the server environment
- **Popups no longer vanish when their tool is missing**: every tool popup — `C-a g`, `d`, `G`, `t`, `/`, `C`, `V`, `M` — goes through `scripts/popup.sh`, which keeps the popup open with the reason and the install command. It also handles fallbacks (`btop`, else `htop`), tools a pipeline relies on (`fzf`, `curl`, `tldr`), and the `gh-dash` extension check that `C-a G` used to carry inline
- **fastfetch and lazygit never installed on x86_64 Linux from GitHub**: fastfetch's assets say `amd64` where the pattern asked for `x86_64`, and lazygit/lazydocker's say `x86_64` where the pattern asked for `amd64`. Each pattern now maps the architecture the way that project names it
- **Health check knows about server installs**: it checks the server tool set, skips language toolchains, and `--fix` runs `install.sh --server` instead of the full workstation install
- **`curl ... | bash` form of the updater could run stale code**: `raw.githubusercontent.com` lags a push by a few minutes and a piped script cannot re-execute itself, so it could pull the newest commit and still finish with the old script's logic. After the pull it now hands over to the installed `~/.config/tmux/update.sh`; the curl form is documented alongside the install one-liner
- **Health check over a non-login shell**: `ssh host '~/.config/tmux/update.sh'` (or the curl form) reported server-mode tools missing because `~/.local/bin` was not on that shell's PATH; the check now adds it itself
- **nvim config never updated on servers**: Lazy rewrites `lazy-lock.json` on every plugin sync, so on any machine other than the one where the config is edited the file was always locally modified and `git pull --ff-only` refused. `update.sh` now discards a `lazy-lock.json`-only change before pulling (the committed version wins and Lazy regenerates it anyway); any other local edit still stops the pull and is reported

### Changed
- `F12` and the new automatic switching share one implementation (`scripts/remote-mode.sh`) instead of two inline command sequences in `tmux.conf`
- Verified against a real Linux server (`tmux 3.4`): hand-typed `ssh` in a window and in a split pane, `C-a t` opening btop on the server, prefix returning on pane and window changes, and cleanup after detach

## [4.5.1] - 2026-09-19

### Added
- **`dotup` / `dotcheck` aliases and `C-a C-u` popup**: update everything without remembering the script path — `dotup` runs `~/.config/tmux/update.sh`, `dotcheck` reports without changing anything, `C-a C-u` runs the same update in a tmux popup
- **Self-updating `update.sh`**: after pulling the repo, it re-executes the freshly pulled copy of itself, so a new updater takes effect in the same run instead of needing a second invocation
- **Repair in `update.sh`**: clones TPM when missing, updates and cleans tmux plugins (it only installed them before), installs `gh-dash` when absent, upgrades the Homebrew formulae these installers manage, and offers to run `install.sh` for anything still missing
- **Shell config lands where your shells read it**: `install.sh` appends to an existing `~/.zshrc`, falling back to an existing `~/.zprofile` before creating a `.zshrc` that was never there — so on a machine with only a `.zprofile` the PATH entries, prompt, and aliases actually take effect. It reports the file it chose and backs that file up
- **`update.sh` flags**: `--check` (report only), `--quick` (repos and plugins only), `--fix` (install missing pieces without asking), `--help`

### Fixed
- **Metals installed but unreachable on macOS**: Coursier puts `metals` and `scalafmt` in `~/Library/Application Support/Coursier/bin`, which is on no default PATH, and Homebrew's `openjdk` is keg-only, so `java` resolved to the macOS stub that has no runtime behind it. The installers now install `openjdk` on macOS, add both locations to PATH in the shell config they write, and add them to their own PATH before probing for the toolchain
- **`command -v java` was a false positive on macOS**: `/usr/bin/java` exists with no JDK behind it, so the health check and the JDK install step both believed Java was present. Both now run `java -version` instead
- **`grep -q` under `set -o pipefail`**: a matching `grep -q` killed its upstream process with SIGPIPE and made the whole pipeline report failure, so checks like "is gh-dash installed?" and "is rust-analyzer installed?" could silently answer "no"
- **Noisy Neovim plugin sync**: `update.sh` now keeps Lazy's full transcript in `~/.local/share/tmux/update-nvim.log` and prints only the plugins blocked by local changes
- **Credential prompts during update**: git fetches run with `GIT_TERMINAL_PROMPT=0`, so an auth failure reports "cannot reach GitHub" instead of hanging on a keychain prompt in a popup
- **`gh dash` popup (`C-a G`) was dead on fresh installs**: the installers set up the GitHub CLI but never the `gh-dash` extension it depends on. `install.sh`, `setup.sh`, `install.ps1`, and `setup-windows.ps1` now install `dlvhdr/gh-dash`, `update.sh` upgrades it, and the `C-a G` binding shows the install command instead of a popup that closes instantly when the extension is missing

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
