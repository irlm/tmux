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
| `C-u` | update everything | | |

## Search and Reference

Quick lookups without leaving tmux. All results open in a popup — press `q` to close.

| Key | Action | Notes |
|-----|--------|-------|
| `e` | web search (DuckDuckGo) | results in `fzf`: Enter opens in browser, Ctrl-W opens in `w3m` |
| `E` | web search (pick scope) | choose from All, Wikipedia, GitHub, StackOverflow, or MDN |
| `a` | ask AI (Claude) | single question, answer shown in popup |
| `M` | man page | system manual pages |
| `C` | cheat.sh | community-driven cheat sheets with syntax highlighting |
| `V` | tldr | simplified command examples (like a short man page) |

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
| `s` | SSH to a host, install this config there if it is missing, and attach its tmux |
| `F12` | toggle remote mode by hand |

`C-a s` asks for a host (anything `ssh` accepts: an alias from `~/.ssh/config`, or `user@host`) and opens it in a new window. The first time you connect to a server that does not have this config, it offers to install it — it copies this machine's own `install.sh` over and runs it with `--server`, so both ends run the same version. You authenticate once; the check, the install, and the attach share one SSH connection.

While a remote tmux is in front of you, the local tmux is in **remote mode**: its prefix is switched off, so every key — `C-a` included — goes to the server's tmux, and the same bindings you use locally (`C-a |`, `C-a t`, `C-a ?`, ...) act on the server. The status bar shows `REMOTE` while it is active.

Remote mode is automatic and does not depend on how you connected. A server running this config announces its tmux through the terminal title (`tmux-remote:<host>`), so it works for a `C-a s` window, an `ssh` you typed by hand in any pane, `mosh`, or a jump host — the moment the remote tmux attaches, keys go to it; the moment it detaches or the connection ends, they come back. It also follows your focus: move to a local window or pane and the local tmux is yours again.

`F12` overrides the automatic choice for the window you are in, until you leave it:

- inside a remote tmux, `F12` gives the local prefix back — that is how you reach `C-a n` to switch local windows
- on a server that does **not** run this config (nothing announces itself), `F12` is how you turn remote mode on by hand

The announcement only happens when the tmux server was started inside an SSH session, so your local tmux never marks itself remote.

The title alone is not trusted. Remote mode needs all three: the program in front is a remote client (`ssh`, `slogin`, `mosh`, `autossh`, `sshpass`, `et`, `tsh`), it is showing something full-screen, and the title carries the marker. A remote tmux that dies with its server never gets to clear its title, and without the other two checks the leftover would make a local `vim` look like a remote tmux; leftovers are also wiped as soon as they are noticed. While remote mode is on it re-checks itself on every status refresh, so an abruptly dropped connection hands the prefix back within a few seconds even though tmux raises no event for it. If you connect through some other program, add it: `set -g @remote_clients "ssh mosh-client my-wrapper"`.

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
| `dotup` | update everything: repos, plugins, gh extensions, CLI tools |
| `dotcheck` | report what is outdated or missing, change nothing |
| `C-a C-u` | same update, in a tmux popup |
| `C-a ?` | open the on-screen cheatsheet |
| `nvim` | open the paired Neovim setup |
