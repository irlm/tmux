# Herdr

[Herdr](https://herdr.dev) is a terminal workspace manager built for coding
agents: a sidebar shows which Claude Code or Codex pane is working, blocked or
done, and agent conversations come back after the server restarts. Herdr is the
desktop multiplexer of this setup; the installer configures it with the same
prefix, keys, popups, theme and status readings as the tmux side, so one set
of habits works on macOS, Linux and Windows, and on the servers where tmux
remains.

tmux and Herdr share the scripts and the action registry; only the glue
differs.

## Install

The default install does it: `install.sh` on macOS and Linux, `install.ps1`
on Windows (see the [installation guide](installation.md)). Herdr is
installed from herdr.dev when missing and configured from this repo either
way. To render the configuration again by hand, after editing
`~/.config/tmux-user/herdr.toml` for example:

```bash
~/.config/tmux/scripts/herdr-config.sh          # macOS, Linux
```

```powershell
pwsh ~\.config\tmux\scripts\herdr-config.ps1   # Windows
```

`install.sh --no-herdr` (Windows: `INSTALL_HERDR=0`) gives a tmux-only
desktop; `install.sh --server --herdr` adds Herdr to a server.

The configuration needs Herdr 0.9.5 or newer. The installers and `dotup`
update an older Herdr first, since an old binary rejects the rendered file
and would stay on its own `ctrl+b` prefix; `dotcheck` reports it. Keys are
read by the Herdr client, so one that was already open keeps its previous
keys until you reload it (`C-a r`, or `ctrl+b shift+r` on a stock config)
or detach and start `herdr` again.

`herdr-config.sh` renders `herdr/config.toml`, one popup binding per row of
`actions.tsv`, and your `~/.config/tmux-user/herdr.toml`, validates the result
with `herdr config check`, writes `~/.config/herdr/config.toml` (a hand-written
config is backed up beside it first), links the `irlm.workbench` plugin and
reloads a running server. `install.sh` does this whenever Herdr is already on
the machine; `update.sh` refreshes it; `doctor.sh` checks it.

The Claude Code and Codex integrations (`herdr integration install claude codex`)
are installed when those CLIs exist. They are what brings a conversation back
into its pane after a restart.

### While Herdr is running

Nothing needs closing. Run the installer, `dotup` or `herdr-config.sh` from a
Herdr pane like any other command: the renderer validates the new config,
writes it and reloads the running server, so new keys and popups work in the
pane next to it straight away. Only the theme is read by the client, so after
a theme change press `C-a r` inside Herdr.

The one exception is Herdr's own binary. A full `dotup` runs `herdr update`,
which installs the new version on disk while the running server keeps the old
one. When that happens, finish what the agents are doing, press `C-a q` to
detach (everything keeps running), and start `herdr` again; the integrations
bring each agent conversation back into its pane. `herdr update --handoff`
attempts the switch live instead.

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
| `Space` `u` | pick text to copy, pick a URL (the same pickers as under tmux) |
| `$` | LLM usage and limits |
| `C-f` | open a `file:line` the pane mentions in your editor |
| `!` | editor cheatsheet |

`ctrl+h/j/k/l` without the prefix move between panes. Helix leaves those keys
to Herdr (its own windows use `C-w`), and its `-a` key sends the selection
into the agent pane of the workspace; see [usage: Editor](usage.md#editor).
With the optional Neovim, the keys also move between its windows, as
vim-tmux-navigator does under tmux: Herdr sends the key to the editor when
one runs in the pane (`scripts/herdr-navigate.sh`), and the paired
[irlm/nvim](https://github.com/irlm/nvim) config hands the focus back at an
edge. Shells lose `ctrl+l` for clear, as they already do
under tmux; type `clear`.

## Working with agents

The loop this setup is built for: an agent works in a pane, the sidebar says
when it needs you or is done, you jump there, review what changed, and send
the next instruction.

| Key | What it does |
|-----|--------------|
| sidebar | agents under their workspace (`herdr_agent_sort=priority` queues them by urgency instead); under each Claude Code or Codex row the task it is on; beside a Claude Code agent `ctx 240k`, the context its next turn re-reads, painted once it passes 100k; under each workspace its branch and `3 files +40 -12`, the uncommitted work |
| `C-a C-o` | jump to the agent that just notified |
| `C-a C-n` `C-a C-p` | next / previous agent |
| `C-a w` | every Herdr agent in a popup: state, workspace, task, context size, how long in that state, directory; the pane shown beside. Enter jumps, `C-r` reads its last 400 lines, `C-s` sends it a prompt, `C-d` reviews its changes. Herdr only: under tmux `C-a w` stays tmux's window tree |
| `C-a C-d` | what changed in the repository behind the pane: one row per file with the diff beside it. Enter opens the file in Helix at its first changed line and comes back to the list; `C-a` sends that file's diff into the agent's input with "About your change in ..."; `C-w` the whole diff; `C-d` switches the diff between `delta` and `difftastic` (syntax-aware); `C-y` copies the path; `C-g` lazygit |
| `C-a C-g` | a worktree per task: pick an existing worktree of this repository or type a branch name. Herdr opens it as a workspace grouped under this one; checkouts live in `~/.herdr/worktrees/<repo>/<branch>` (`worktree_dir` in `options.env`). `C-a` in the picker, instead of Enter, also starts a fresh agent there (`claude`, or `worktree_agent`) |
| `- a` in Helix | send the selection, or the line, into the agent's input |

The sidebar information comes from `scripts/agent-events.sh`, which the
`irlm.workbench` plugin runs on every agent state change: it journals the
change (`~/.local/share/tmux/agent-journal.tsv`, what `C-a w` uses for the
time in state) and reports the size of the uncommitted work in that pane's
repository as the workspace's `$changes` token. Nothing polls.

The sidebar keeps each agent under its workspace, so the list stays the map
of where you were working. `herdr_agent_sort=priority` in `options.env`
queues them by urgency instead: blocked first, then done, then working.

### One session per task

Every turn of an agent re-reads its whole conversation before doing
anything. That is cheap per token and large in total: a session that has
grown to 500k tokens pays for 500k on every prompt, whatever the prompt is.
The `ctx` figure beside each Claude Code agent is that number, read from the
session's transcript after each turn at no cost, and it changes colour past
`ctx_warn_k` (thousands of tokens, default 100). When it does, the next
unrelated task belongs in a new session: `C-a C-g`, a branch name, `C-a`
gives it a worktree, a workspace and a fresh agent in one step.

[model-router](https://github.com/irlm/model-router) measures the same
thing with prices attached, routes agent calls to the model each kind of
work needs, and shows what a change saved. `install.sh --router` (Windows:
`INSTALL_ROUTER=1`) installs its Claude Code plugin; nothing installs it by
default, since it changes how Claude Code behaves.

The installers (`install.sh`, `dotup`, `install.ps1`) also put Herdr's own skill file in `~/.claude/skills/herdr`,
so a Claude Code running in a Herdr pane can split panes, start a helper
agent beside itself, prompt it and wait for it (the skill only acts when
`HERDR_ENV=1`). `herdr --skill` prints the copy matching the installed Herdr.

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
[`quota-axi`](https://github.com/kunchenguid/quota-axi) when it is installed
(`npm install -g quota-axi`; the installers do it where `npm` exists, and
Node itself comes with `--full` / `INSTALL_FULL=1`);
the first Claude reading needs `quota-axi --allow-keychain-prompt` once so it
may read the credential from the Keychain. Nothing runs until the popup opens.

## Theme and status bar

The theme chosen with `C-a C-t` carries over: Nord and Catppuccin map onto
Herdr's own themes, High contrast onto Nord with brighter tokens, and the
palette's full text colour replaces Herdr's dim status token so the tab bar's
date and readings read like the tmux status line. The other eight picks are
Herdr's own dark themes (Tokyo Night, Dracula, Gruvbox, One Dark, Solarized,
Kanagawa, Rose Pine, Vesper): Herdr shows the theme as it ships it, with only
the status token raised, and lazygit, fzf and the prompt follow with the same
colours (see [customization](customization.md) for the ones lightened there).

Herdr's own picker (`C-a C-s`, theme) still works, and is where its light
themes and `terminal` are: Herdr writes the choice
into the rendered file, the next render notices it, records it as
`herdr_theme` in `options.env`, and keeps it with only the status token raised
to that theme's text colour; lazygit, fzf and the prompt stay on the last
`C-a C-t` palette. The next `C-a C-t` pick replaces it. Themes
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
| `~/.config/tmux-user/options.env` | `name=value` lines for the options tmux reads as `@name`: `popup_size`, `ai_command`, `project_roots`, `project_depth`, `cpu_process_threshold`, `special_days`, `herdr_agent_sort` (`priority` or `spaces`), `worktree_dir`, `worktree_agent` (what `C-a` in the worktree picker starts, default `claude`), `ctx_warn_k` (context warning size in thousands of tokens, default 100), `editor` (what `C-a v` opens; `C-a C-v` writes it) |
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
- The tab bar readings come from `scripts\status_right.ps1` every fifteen
  seconds: network rate, CPU, memory and battery from CIM and the adapter
  counters, and the busiest process beside a high CPU reading from the
  change in each process's CPU time since the last sample.
- `ctrl+hjkl` navigation works the same way through Git Bash.
- Tools the popups call (fzf, lazygit, bat, fastfetch, python) come from Scoop
  through `install.ps1`; `python3` resolves to Scoop's `python`.
- The LLM usage card (`C-a $`) is drawn with `curses`, which Windows Python
  lacks: `install.ps1` adds the `windows-curses` package
  (`python -m pip install windows-curses`). Where that package has no build
  for the installed Python (ARM64, or a Python newer than the package), the
  popup shows the plain report instead: any key closes it when it fits the
  popup, and it opens in `less` (`q` closes) when it does not.

Rerunning `install.ps1` updates the checkout and re-renders the Herdr config,
the way `dotup` does on Unix; `C-a C-u` runs it from Herdr. The installer
wants an Administrator PowerShell (fonts, winget), so from a Herdr started
without one, update from any PowerShell window instead; Herdr can stay open:

```powershell
git -C "$HOME\.config\tmux" pull --ff-only
pwsh "$HOME\.config\tmux\scripts\herdr-config.ps1"
```

Then `C-a r` inside Herdr for a theme change. Verified on a
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
bash tests/herdr-live-check.sh             # the agent features against a throwaway session, PASS/FAIL lines (Git Bash on Windows)
scripts/herdr-config.sh --check            # render and validate without installing
herdr --session wbtest server              # a throwaway headless session for experiments
```
