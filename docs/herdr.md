# Herdr

[Herdr](https://herdr.dev) is a terminal workspace manager built for coding
agents: a sidebar shows which Claude Code or Codex pane is working, blocked or
done, and agent conversations come back after the server restarts. This repo
configures Herdr with the same prefix, keys, popups, theme and status readings
as its tmux setup, so one set of habits works on macOS, Linux and the machines
where tmux was never an option.

tmux stays as it was. The two share the scripts and the action registry; only
the glue differs.

## Install

macOS and Linux:

```bash
bash install.sh --herdr          # installs Herdr too, then configures it
scripts/herdr-config.sh          # Herdr already installed: render and link
```

Windows (PowerShell):

```powershell
$env:INSTALL_HERDR = "1"; irm https://raw.githubusercontent.com/irlm/tmux/main/install.ps1 | iex
pwsh ~\.config\tmux\scripts\herdr-config.ps1   # Herdr already installed: render and link
```

`herdr-config.sh` renders `herdr/config.toml`, one popup binding per row of
`actions.tsv`, and your `~/.config/tmux-user/herdr.toml`, validates the result
with `herdr config check`, writes `~/.config/herdr/config.toml` (a hand-written
config is backed up beside it first), links the `irlm.workbench` plugin and
reloads a running server. `install.sh` does this whenever Herdr is already on
the machine; `update.sh` refreshes it; `doctor.sh` checks it.

The Claude Code and Codex integrations (`herdr integration install claude codex`)
are installed when those CLIs exist. They are what brings a conversation back
into its pane after a restart.

Run `herdr` in a terminal window that is not inside tmux, so tmux does not
swallow `C-a`.

## Keys

Everything from `C-a ?` applies. The differences from tmux:

| Key | Herdr |
|-----|-------|
| `N` `.` `,` | Herdr's own new-workspace and rename prompts |
| `]` | next tab (`n` stays the notes popup) |
| `S` `W` | workspace picker, go-to navigation |
| `Q` | close workspace; `q` detaches and leaves everything running |
| `;` `Tab` | last pane, next pane |
| `C-e` | open the scrollback in your editor |
| `C-n` `C-p` `C-o` | next / previous agent, jump to what just notified |
| `b` | show or hide the sidebar |
| `F1` `C-s` | Herdr's live key list and settings |
| `Space` `u` | pick text to copy, pick a URL (stand-ins for tmux-thumbs and fzf-url) |
| `$` | LLM usage and limits |

`ctrl+h/j/k/l` without the prefix move between panes and, inside Neovim,
between its windows, as vim-tmux-navigator does under tmux. Herdr sends the
key to the editor when one runs in the pane (`scripts/herdr-navigate.sh`),
and the paired [irlm/nvim](https://github.com/irlm/nvim) config hands the
focus back at an edge. Shells lose `ctrl+l` for clear, as they already do
under tmux; type `clear`.

## Popups and the plugin

Every `actions.tsv` row becomes a `[[keys.command]]` popup sized by
`popup_size` and a pane of the `irlm.workbench` plugin, so the same tools open
from keys, from `herdr plugin pane open`, and from plugin menus. Rows whose
`hosts` column says `tmux` (resurrect, F12 remote mode) are left out; rows
marked `herdr` exist only here.

Under Herdr the popups read the pane behind them with `herdr pane read`, the
project switcher (`C-a o`) creates or focuses a workspace per project, and
`C-a s` opens ssh in a new tab. For a server you use often, `herdr machine add`
puts its agents in the same sidebar; see Herdr's own documentation.

## LLM usage (`C-a $`)

`scripts/llm_usage.py` opens a card with one tab per agent on the machine:
Claude Code, Codex and Antigravity from their transcripts of the last week
(one cached aggregate per file), plus Grok, Copilot, Cursor and Kimi when
`quota-axi` reports them set up, with their live windows only. Each tab shows
the limit windows with their reset time, tokens by day and tokens by model.
Tab, the arrows or the digits switch tabs, `r` refreshes, `q` closes. Live rate-limit windows come from
`quota-axi` when it is installed;
the first Claude reading needs `quota-axi --allow-keychain-prompt` once so it
may read the credential from the Keychain. Nothing runs until the popup opens.

## Theme and status bar

The theme chosen with `C-a C-t` carries over: Nord and Catppuccin map onto
Herdr's own themes, High contrast onto Nord with brighter tokens, and the
palette's full text colour replaces Herdr's dim status token so the tab bar's
date and readings read like the tmux status line.

Herdr's own picker (`C-a C-s`, theme) still works: Herdr writes the choice
into the rendered file, the next render notices it, records it as
`herdr_theme` in `options.env`, and keeps it with only the status token raised
to that theme's text colour. The next `C-a C-t` pick replaces it. Themes
are client-side in Herdr, so after any change press `C-a r` inside Herdr:
`herdr server reload-config`, which the renderer runs, refreshes the server
but not the colours you are looking at.
The right edge of the tab bar runs `status_right.sh --plain` every five
seconds; the script reuses its five-second sample, so the cost is one short
process per interval. Herdr paints every entry in one colour and strips
escape codes, so the readings are told apart by icon rather than colour.

A patch that lets each entry name its own colour is kept alongside this repo
(see the changelog) and awaits Herdr's maintainers; on a Herdr built with it,
set `herdr_status_colors=on` in `options.env` and the renderer emits one entry
per reading, painted like the tmux status line (`status_right.sh --part cpu`
and friends read the same cached sample, so four entries still measure once).
A stock Herdr rejects that config, which `herdr config check` reports before
anything is installed.

## Personal settings

| File | Purpose |
|------|---------|
| `~/.config/tmux-user/options.env` | `name=value` lines for the options tmux reads as `@name`: `popup_size`, `ai_command`, `project_roots`, `project_depth`, `cpu_process_threshold`, `special_days` |
| `~/.config/tmux-user/herdr.toml` | appended verbatim to the rendered config: `[theme.custom.light]`, more `[[keys.command]]`, anything the template does not define |
| `~/.config/tmux-user/herdr-plugin/` | the generated plugin; linked, not copied |

Rerun `scripts/herdr-config.sh` (or `dotup`) after editing them. `herdr
config check` reports a conflict as "kept ... disabled ...": the earlier
binding wins.

## Windows

Herdr runs natively on Windows and `scripts\herdr-config.ps1` renders the same
file there, into `%APPDATA%\herdr\config.toml`: the keys, the theme, the
plugin and your `herdr.toml` are identical. The differences come from the
popups being Bash scripts:

- They run through Git Bash when it is installed (Git for Windows, or Scoop's
  git, which `install.ps1` installs); `HERDR_BASH` names another bash. Without
  Git Bash, WSL is used with this repo installed inside the distribution;
  without either, the popups are left out and the native Herdr keys remain.
- The tab bar shows the hostname and the clock; the hardware readings need
  Unix tools.
- `ctrl+hjkl` navigation works the same way through Git Bash.
- Tools the popups call (fzf, lazygit, bat, fastfetch, python) come from Scoop
  through `install.ps1`; `python3` resolves to Scoop's `python`.

Rerunning `install.ps1` updates the checkout and re-renders the Herdr config,
the way `dotup` does on Unix; `C-a C-u` runs it from Herdr. Verified on a
Windows 11 ARM virtual machine from a clean install: every package through
Scoop, Herdr itself, the rendered config, the plugin, the popups through Git
Bash, and `ctrl+hjkl` navigation.

## What is different from tmux

- Sessions are workspaces and windows are tabs; `C-a o` lists live workspaces
  first, then projects.
- Copy mode has `v`, `y`, `/`, `n`; no rectangle selection and no `H`/`L`.
- No resurrect: Herdr restores layout, agent conversations (with the
  integrations) and, with `pane_history`, recent pane contents.
- `C-a F12` remote mode and the server bootstrap belong to tmux; Herdr's
  `machine add` is the equivalent.

## Checks

```bash
python3 -m unittest tests.test_herdr -v    # fake herdr on PATH; real one only validates
scripts/herdr-config.sh --check            # render and validate without installing
herdr --session wbtest server              # a throwaway headless session for experiments
```
