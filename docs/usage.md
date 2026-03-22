# Usage and Keybindings

## Prefix

This setup uses `C-a` as the tmux prefix instead of tmux's default `C-b`.

Examples:

- `C-a c`: new window
- `C-a g`: `lazygit` popup
- `C-a ?`: cheatsheet

## First-Day Workflow

If you just installed the project, these are the commands and keys you will probably use first:

| Command / Key | Action |
|---------------|--------|
| `tmux` | start tmux |
| `C-a c` | new window |
| `C-a \|` | split horizontally |
| `C-a -` | split vertically |
| `C-a h j k l` | move between panes |
| `C-a o` | open the sessionizer/project switcher |
| `C-a g` | open `lazygit` |
| `C-a r` | reload the tmux config |
| `nvim` | open Neovim |

## Popups

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `g` | `lazygit` | `n` | quick notes |
| `G` | `gh dash` | `o` | sessionizer |
| `d` | `lazydocker` | `?` | cheatsheet |
| `t` | `btop` or `htop` | `/` | search pane history |
| `i` | system info | `f` | floating shell |

## Search and Reference

| Key | Action |
|-----|--------|
| `e` | web search with DuckDuckGo via `fzf` |
| `E` | web search with source picker |
| `a` | ask AI in a popup |
| `M` | man page lookup |
| `C` | `cheat.sh` lookup |
| `V` | `tldr` lookup |

## Panes

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `\|` | split horizontal | `z` | zoom toggle |
| `-` | split vertical | `x` | kill pane |
| `h j k l` | navigate | `b` | break pane into window |
| `H J K L` | resize | `@` | join pane |
| `{ }` | swap panes | `m` | mark pane |
| `q` | show pane numbers | | |

## Windows and Sessions

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `c` | new window | `N` | new session |
| `,` | rename window | `.` | rename session |
| `X` | kill window | `S` | choose session |
| `< >` | reorder windows | `BkSp` | switch to last session |
| `W` | choose window | `Q` | kill all sessions with confirmation |
| `C-n` | automatic rename on | `D` | choose client to detach |
| `Y` | synchronize panes on or off | | |

## SSH and Nested Tmux

| Key | Action |
|-----|--------|
| `s` | SSH to a host and auto-attach or create remote tmux |
| `F12` | toggle local prefix off or on for nested tmux |

When nested mode is active, the status bar shows `REMOTE` and keys go to the inner tmux until you press `F12` again.

## Copy Mode

Enter copy mode with `C-a [`.

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `v` | begin selection | `H` / `L` | start / end of line |
| `y` | yank and exit | `/` / `?` | search down / up |
| `C-v` | block selection | `Esc` | exit copy mode |

## Plugins and Persistence

| Key | Action |
|-----|--------|
| `I` | install tmux plugins |
| `u` | open `fzf` URL picker |
| `Space` | `tmux-thumbs` text hints |
| `C-s` | save session |
| `C-r` | restore session |
| `r` | reload config |

Sessions are persisted with `tmux-resurrect` and `tmux-continuum`. Auto-save runs every 15 minutes.

## Utilities

| Key | Action |
|-----|--------|
| `T` | clock mode |
| `C-l` | clear pane history |

## Shell Aliases

These are the aliases documented for the shell setup that ships with the project:

| Alias | Command | Alias | Command |
|-------|---------|-------|---------|
| `gs` | `git status` | `gp` | `git push` |
| `gl` | `git log --graph` | `gpl` | `git pull` |
| `lg` | `lazygit` | `ta` | new tmux session from directory name |
| `taa` | attach existing tmux session | `z` | `zoxide` smart cd |

## Handy Commands

| Command | Action |
|---------|--------|
| `~/.config/tmux/update.sh` | update tmux, Neovim, and plugins |
| `C-a ?` | open the on-screen cheatsheet |
| `nvim` | open the paired Neovim setup |
