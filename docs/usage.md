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

## SSH and Remote Servers

Install this config on a server and your local keys work there unchanged: while a remote tmux is in front of you, `C-a t` opens btop on the server, `C-a g` opens lazygit on the server, `C-a |` splits the server's window. The local tmux notices the remote one and steps aside. It does not matter whether you connected with `C-a s`, typed `ssh` yourself, or use a split pane.

| Key | Action |
|-----|--------|
| `s` | SSH to a host in a new window; install this config there if it is missing; attach its tmux |
| `P` | the same, in a pane split beside the current one |
| `F12` | override remote mode for the current window (the way out, or the way in on a server without this config) |

### Connecting

**`C-a s`** asks for a host — anything `ssh` accepts: an alias from `~/.ssh/config`, or `user@host` — and opens it in a new window. If the server does not have this config yet, it offers to install it, using the same `install.sh` as this machine in `--server` mode, so both ends run the same version. You authenticate once: the check, the install, and the attach share one SSH connection. A server without tmux gets a plain shell; an unreachable host shows ssh's error and waits for a key instead of closing the window.

**`C-a P`** does the same in a pane split beside the current one — for a server console next to local work. The split opens in the current pane's directory, like `C-a |`.

**By hand** works just as well. Type `ssh host` in any window or split pane, start or attach tmux there, and remote mode switches on by itself.

**Getting out** — remote mode follows your focus, so leave the remote pane and you are local again:

- another window: press `F12`, then `C-a n` (or any window key). `F12` gives the local prefix back for as long as you stay in that window.
- another pane in a split: `F12`, then `C-a l` (or `h` `j` `k`). Landing on the local pane returns the prefix; moving back to the remote pane hands it over again.
- for good: detach the remote tmux (`C-a :` then `detach`) or exit the ssh session.

### What the status bar shows

`REMOTE` on the left means the local prefix is off and every key, `C-a` included, is going to the server. Below it you see the server's own status bar, since the remote tmux is drawing the pane — that is the quickest way to tell which machine `C-a t` will hit.

### How detection works

A tmux server started inside an SSH session loads `remote.conf` and sets its terminal title to `tmux-remote:<host>`. Your local tmux sees that title on the pane, and switches the prefix off when three things hold at once: the program in the pane is a remote client (`ssh`, `slogin`, `mosh`, `mosh-client`, `autossh`, `sshpass`, `et`, `tsh`), it is showing something full-screen, and the title carries the marker. The three together mean a stale title cannot capture the keyboard: a remote tmux that dies with its server never clears its title, and without the other checks a local `vim` in that pane would be mistaken for it. Leftover markers are wiped as soon as they are seen.

Your local tmux never announces itself, because it was not started under SSH. If you connect through some other program, add it to the client list:

```
set -g @remote_clients "ssh mosh-client my-wrapper"
```

Re-evaluation is event driven — window change, pane change, window rename, title change — and, while remote mode is on, also runs on every status refresh (5 s), so a dropped connection hands the prefix back within a few seconds even though tmux raises no event for a program exiting.

### Servers without this config

Nothing announces itself, so the local tmux keeps its prefix. Press `F12` in that window to hand the keys over by hand, and `F12` again to take them back. Or run `C-a s` once and accept the install.

### Keeping servers current

The server gets the same `update.sh` as your workstation. Run `~/.config/tmux/update.sh` there (or `dotup`, once the server's shell config has the alias), and it pulls this repo, updates plugins, and reloads its tmux config. An old server updater pulls the new one and re-executes it, so one run is always enough.

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
