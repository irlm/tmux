# Customization and diagnostics

Requires tmux **3.2 or newer**, Bash or Zsh, and Python 3. Installers use `tools.tsv` for the required tools in each profile. Docker and language toolchains remain workstation extras.

## Choose a theme

Press **`C-a C-t`** (Ctrl-a, then Ctrl-t), or find **Choose theme** in `C-a F`.

- **Nord:** the existing palette with brighter red and secondary text.
- **Catppuccin Macchiato:** based on the existing Catppuccin prompt theme.
- **High contrast:** a Nord-based option with brighter text and status colors.

The picker previews normal, selected, added and removed text. Enter applies and saves; Esc leaves the choice unchanged. The choice persists in `~/.config/tmux-user/theme`, outside the Git checkout. Run `scripts/themes.sh apply nord`, `scripts/themes.sh apply catppuccin`, or `scripts/themes.sh apply contrast` to select directly.

Tmux status, pane surfaces/borders, popups, help and fzf use the selected palette. On versions supporting `pane-colours`, the 16 ANSI colors also follow it. Older tmux versions retain their terminal ANSI palette while the explicit tmux/lazygit colors still apply. The terminal application's own configuration is preserved; apps with independent RGB themes may keep those colors.

Reopen lazygit with **`C-a g`** to use the chosen palette. Its normal config is loaded first, followed by a generated appearance overlay at `~/.config/tmux-user/lazygit.yml`. Custom commands, bindings and diff renderers remain in the original config. The managed launcher also supplies readable Git diff colors through process-local environment settings; global Git configuration is preserved. `lg` in managed full shells uses this launcher too.

Oh My Posh prompts use a generated `~/.config/tmux-user/prompt.omp.json` in new shells. Existing shells may retain their old prompt until reopened. Shell setup also sources `shell/theme-env.sh` so direct lazygit and fzf inherit the chosen palette in new shells. Lightweight server prompts retain their existing prompt implementation.

Palette definitions live in `themes.json`. The default Nord red is `#f2a1a8`: about **6.2:1** against its normal background and **5.0:1** against its selected-row background. All offered text/status palette roles are tested at **4.5:1 or better** against both surfaces. Generated theme files are managed outputs; put persistent palette changes in the catalog rather than editing generated files. `TMUX_THEME_DIR` can select a different user-owned state directory.

## Personal settings

Keep personal tmux settings in `~/.config/tmux-user/local.conf` (recommended), or in the Git-ignored `~/.config/tmux/local.conf`. Settings load after plugins and action bindings. Updates preserve both files. The external file also survives replacing the managed repository.

```tmux
# desktop (default), server, compact, or auto (detect the Neovim .server marker)
set -g @profile compact
set -g @history_limit 20000
set -g @ascii on
set -g @popup_size 90%

# Each project root is a separate line. Spaces within a root are literal.
set -g @project_roots "/home/me/projects\n/home/me/work repos"
set -g @project_depth 6

# Optional executable wrapper receiving one literal question argument.
set -g @ai_command my-ai-wrapper

# Name the busiest process beside the CPU reading above this percentage (off: never, 0: always)
set -g @cpu_process_threshold 30
```

Under Herdr, where there is no tmux option store, the same names go in `~/.config/tmux-user/options.env` as `popup_size=90%` lines; see [Herdr](herdr.md).

Reload with `C-a r`. The compact profile keeps a smaller history and status area; narrow clients automatically omit system metrics. ASCII mode replaces custom status icons and uses simple pane borders. Existing pane history is not trimmed until panes are recreated.

`@project_roots` also accepts an actual multiline quoted value. `TMUX_PROJECT_ROOTS` is a newline-separated environment alternative; `TMUX_PROJECT_DEPTH` sets its discovery depth. Without an override, projects are searched under `~/projects`, `~/Projects`, and `~/.config`. Project discovery includes `.git` directories and Git worktree `.git` files, and prunes plugin, vendor, build-cache and dependency directories. Recent projects appear first; live sessions are listed separately. Canonical paths identify projects, so two repositories named `api` remain distinct. Paths with tabs or newlines are excluded from this line-oriented picker.

## Special day art

The first tmux attachment on a special day opens a short, dismissible ASCII
greeting. New Year's Day, July 4 and New Year's Eve include animated fireworks.
Halloween, Valentine's Day, St. Patrick's Day, Thanksgiving and Christmas have
their own moving scenes: flying bats, floating hearts, clover sparkles, a
strutting turkey, and falling snow. Dates follow the machine's local calendar; Thanksgiving is
the fourth Thursday in November. Ordinary days stay quiet.

Press **`C-a A`**, or choose **Special day art** in `C-a F`, to preview and replay
any celebration whenever you like. Press `r` to replay inside the art, or Enter,
`q` or Esc to close it. Each replay gets a fresh arrangement. Press `n` or `p`
to move to the next or previous holiday inside the same popup. Fireworks mix
round bursts, cascading willow sparks and hearts; Halloween includes a floating
ghost and Christmas has a shooting star.

July 4 fireworks build a large **U S A** from their sparks. **U... S... A...**
burst in different places across the sky, with other fireworks alongside them.
The letters then gather quickly into **USA** for the finale. Year digits follow
the same sequence. The complete word or year remains in place after playback.
New Year fireworks form the celebration year: December 31, 2026 welcomes **2027**, and January 1, 2027
shows **2027**. Manual New Year replays on other dates look ahead to the next
January 1. Date previews and the picker use the same calendar rules. Smaller
terminals fall back to readable single-line lettering.

Letter fireworks run once for about three seconds; other scenes use four seconds.
Both use 12 frames per second, on a canvas capped at 96 by 16 characters. Only changed rows are written
to the terminal. Finished manual scenes sleep until a key is pressed; animation
uses no background process or timer after the popup closes.
Automatic greetings close on their own and run once per date on each machine,
even if tmux restarts. The date stamps live in `~/.local/share/tmux/special-days/`.
Replaying an event does not change those stamps. Small terminals below 60 columns
or 18 rows skip automatic greetings; the manual picker remains available.

A small ASCII motif also appears beside the date in the status bar when the
terminal is at least 100 columns wide. These options in your personal config
control automatic greetings, status motifs, and animation:

```tmux
set -g @special_days off        # disable automatic greetings and status motifs
set -g @special_days_motion off # use static drawings for all celebrations
```

Reload with `C-a r`. Manual replay still works when automatic greetings are off.
To preview a date from the command line:

```bash
python3 ~/.config/tmux/scripts/special_days.py --date 2026-10-31 --plain
python3 ~/.config/tmux/scripts/special_days.py --play july-4
```

## Command discovery

Press **`C-a F`** for a searchable command palette. It shows each action's key and dependency availability. **`C-a ?`** shows one grouped shortcut reference. It uses the popup’s actual interior width: one column below 96 cells, two columns from 96–143, and three columns from 144 upward. Keys and descriptions align within each column; long descriptions wrap with a hanging indent. Main tmux shortcuts come first, followed by tool-specific references. Scrolling and search remain available in `less`. Close and reopen after resizing the terminal.

`actions.tsv` is the shared registry for popup bindings, the palette, and action help; its `hosts` column says whether a row applies to tmux, Herdr, or both, and an optional `size` column (`100x36` in cells, or percentages) fits one popup to its content instead of the shared `@popup_size`. `help.tsv` supplies the remaining shortcuts with the same column. The renderer is `scripts/help.py`; `cheatsheet.txt` is a plain-text fallback generated with `python3 scripts/help.py --width 100 --plain`. Dependency availability stays in the command palette.

Search, AI, SSH, manual, tldr, and rename prompts now read input inside their popup/window. Text is passed as arguments, so quotes and shell expressions remain literal. Use SSH aliases for ports, jump hosts and other options. For a custom AI provider, point `@ai_command` at a wrapper executable; the default `claude` command is invoked with `-p`.

Notes with an existing name open that note without rewriting it. Cancel a new-note name with Esc followed by Enter. `EDITOR` names an executable; use a wrapper executable when editor flags are needed.

## Health checks and updates

- `dotcheck` or `~/.config/tmux/update.sh --check`: compare repository heads without fetching, then verify tools, tmux version, config syntax, plugins and clipboard capability information. Required failures return a nonzero exit status.
- `~/.config/tmux/scripts/doctor.sh`: run environment checks without contacting repository origins.
- `dotup --quick`: update repositories, tmux and Neovim plugins, and GitHub extensions; skip package upgrades.
- `dotup --fix`: update, then offer no-prompt repair for missing required tools.

Each failed update component is reported in the final summary. Full transcripts are in `~/.local/share/tmux/update-logs/`. Custom Git edits retain normal merge protection; resolve a blocked pull in that repository and rerun. When Neovim's only local change is its generated `lazy-lock.json`, the updater saves both its staged and working versions in a Git stash before pulling upstream's lockfile. Lazy sync can then regenerate it. Inspect these backups with `git -C ~/.config/nvim stash list`; they are retained rather than automatically reapplied or dropped. `--check` never creates a stash or changes files. Clipboard support is reported when the attached terminal advertises it; copying text and pasting it back remains the end-to-end check.

If the Neovim repository update or lockfile backup fails, plugin synchronization
is skipped so it cannot rewrite that repository's local state.

Hardware samples and network counters use a private `~/.cache/tmux/` directory and atomic writes. Battery readings are sampled at most once per minute. Repeated status renders share five-second samples, and SSH status detection shares one process snapshot per active pane. SSH status height belongs to its session; clients attached to that same session share its height.

## Installer behavior

Default, server and full Unix installs share config replacement and shell helpers. A replacement is cloned into a temporary sibling directory first. Existing custom configs move to a timestamped `.backup.*` sibling only after the clone succeeds. A failed clone leaves the existing config in place. Windows uses the same staging and backup behavior.

Shell integration follows `$SHELL`; set `TMUX_TARGET_SHELL=bash` or `TMUX_TARGET_SHELL=zsh` to choose explicitly. Personal shell files are backed up before adding a managed include. Managed integration lives in `~/.config/tmux-user/shell.bash` or `shell.zsh`. Full setup retains its fuller shell defaults under `shell/full.bash` and `shell/full.zsh` without replacing the personal rc file. Zsh uses `.zshrc`. Bash adds the same include to `.bashrc` and the active login profile; the managed integration runs once when a login profile already sources `.bashrc`.

Starting tmux never clones plugins or requires network access. Installers bootstrap TPM; if tmux is not running, start it and press `C-a I` to install the configured plugins. The custom renderer owns battery/network metrics, so the redundant battery and network-speed plugins are no longer required.

## Development checks

```bash
shellcheck -S warning -x install.sh setup.sh update.sh scripts/*.sh
python3 -m unittest discover -s tests -v
pwsh -NoProfile -NonInteractive -File tests/test-windows.ps1
```

The Python suite uses temporary data directories, command doubles, and a separate tmux socket. It needs permission to create local sockets. CI runs the Unix suite on Ubuntu/macOS and PowerShell preservation checks on Windows. No live SSH deployment or package installation occurs in these tests.
