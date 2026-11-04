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

```bash
bash install.sh --herdr          # installs Herdr too, then configures it
scripts/herdr-config.sh          # Herdr already installed: render and link
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

`scripts/llm_usage.py` reads the Claude Code and Codex transcripts touched in
the last week, caches one aggregate per file, and shows tokens by day and by
model for each agent. Live rate-limit windows come from
`quota-axi` when it is installed;
the first Claude reading needs `quota-axi --allow-keychain-prompt` once so it
may read the credential from the Keychain. Nothing runs until the popup opens.

## Theme and status bar

The theme chosen with `C-a C-t` carries over: Nord and Catppuccin map onto
Herdr's own themes, High contrast onto Nord with brighter tokens, and the
palette's secondary text colour replaces Herdr's dim status token so the tab
bar's date and readings pass the same contrast check as the tmux status line.
The right edge of the tab bar runs `status_right.sh --plain` every five
seconds; the script reuses its five-second sample, so the cost is one short
process per interval.

`C-a i` draws a small image beside the system information when the terminal
can show one (Ghostty, kitty, WezTerm; Herdr passes it through). Put your own
PNG at `~/.config/tmux-user/logo.png` or name one with `info_logo=` in
`options.env`; otherwise macOS converts a system icon once into the cache.

## Personal settings

| File | Purpose |
|------|---------|
| `~/.config/tmux-user/options.env` | `name=value` lines for the options tmux reads as `@name`: `popup_size`, `ai_command`, `project_roots`, `project_depth`, `info_logo`, `special_days` |
| `~/.config/tmux-user/herdr.toml` | appended verbatim to the rendered config: `[theme.custom.light]`, more `[[keys.command]]`, anything the template does not define |
| `~/.config/tmux-user/herdr-plugin/` | the generated plugin; linked, not copied |

Rerun `scripts/herdr-config.sh` (or `dotup`) after editing them. `herdr
config check` reports a conflict as "kept ... disabled ...": the earlier
binding wins.

## What is different from tmux

- Sessions are workspaces and windows are tabs; `C-a o` lists live workspaces
  first, then projects.
- Copy mode has `v`, `y`, `/`, `n`; no rectangle selection and no `H`/`L`.
- No resurrect: Herdr restores layout, agent conversations (with the
  integrations) and, with `pane_history`, recent pane contents.
- `C-a F12` remote mode and the server bootstrap belong to tmux; Herdr's
  `machine add` is the equivalent.
- Windows: Herdr runs natively there, but these popups are Bash scripts;
  `install.ps1` does not configure Herdr yet.

## Checks

```bash
python3 -m unittest tests.test_herdr -v    # fake herdr on PATH; real one only validates
scripts/herdr-config.sh --check            # render and validate without installing
herdr --session wbtest server              # a throwaway headless session for experiments
```
