#!/usr/bin/env bash
# Switch the local tmux between "local" and "remote" key handling. In remote
# mode the prefix is off, so every key — C-a included — reaches the inner
# tmux running on the server.
#
#   remote-mode.sh auto [target]            decide from what the current pane shows
#   remote-mode.sh window-changed [target]  forget F12 overrides, then auto
#   remote-mode.sh toggle-on  [target]      F12: force remote mode for this window
#   remote-mode.sh toggle-off [target]      F12: force local mode for this window
#   remote-mode.sh title-reset <tty>        server side: clear the marker on detach
#
# A pane counts as remote when either
#   - ssh-remote.sh is running in it (@remote, a pane option), or
#   - all three hold: the program in front is a remote client (ssh, mosh, ...),
#     it is showing something full-screen, and the terminal title carries the
#     marker a server-side tmux sets (remote.conf) — which is how an ssh typed
#     by hand, mosh, or a jump host is picked up too.
# The title alone is not trusted: a remote tmux that dies with its server never
# gets to reset it, and the stale marker would turn a local vim into a "remote
# tmux". Stale markers are also wiped whenever they are seen.
# Set @remote_clients (space separated) to extend the list of client programs.
# F12 overrides the decision for the current window until you leave it.
#
# target is anything tmux accepts for -t; it is resolved to its session,
# because prefix and key-table are session options.
MARKER="tmux-remote:"
mode="${1:-auto}"

if [ "$mode" = "title-reset" ]; then
    tty="${2:-}"
    # Runs on the server from the client-detached hook. The detached client's
    # terminal is the ssh pty; resetting its title is what tells the local tmux
    # that the remote tmux is gone.
    [ -n "$tty" ] && [ -w "$tty" ] && printf '\033]2;%s\033\\' "$(hostname -s 2>/dev/null || hostname)" > "$tty"
    exit 0
fi

target="${2:-${TMUX_PANE:-}}"
if [ -n "$target" ]; then
    session=$(tmux display-message -p -t "$target" '#{session_id}' 2>/dev/null)
else
    session=$(tmux display-message -p '#{session_id}' 2>/dev/null)
fi
[ -z "$session" ] && exit 0

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# The REMOTE indicator re-runs "auto" on every status refresh. No tmux event
# fires when the program in a pane exits, so without this a remote tmux that
# dies abruptly would leave the prefix off at a local shell. It only polls
# while remote mode is on; the script prints nothing, so the label is unchanged.
apply_on() {
    tmux set -t "$session" prefix None \; \
         set -t "$session" key-table off \; \
         set -t "$session" status-left "#[bg=colour1,fg=colour15,bold]  REMOTE #[default] #($SELF auto '#{session_id}')" \; \
         if -F -t "$session" '#{pane_in_mode}' 'send-keys -X cancel' \; \
         refresh-client -S >/dev/null 2>&1
}

apply_off() {
    tmux set -u -t "$session" prefix \; \
         set -u -t "$session" key-table \; \
         set -u -t "$session" status-left \; \
         refresh-client -S >/dev/null 2>&1
}

REMOTE_CLIENTS="$(tmux show -gqv @remote_clients 2>/dev/null)"
REMOTE_CLIENTS="${REMOTE_CLIENTS:-ssh slogin mosh mosh-client autossh sshpass et tsh}"

# An attached inner tmux always holds the alternate screen, so a marker on a
# pane that is not full-screen is left over from one that is gone. Writing the
# title sequence to the pane's tty is how to retitle it without select-pane -T,
# which would also move the focus.
sweep_stale_markers() {
    local line pane alt tty title
    tmux list-panes -s -t "$session" -F '#{pane_id}|#{alternate_on}|#{pane_tty}|#{pane_title}' 2>/dev/null |
    while IFS= read -r line; do
        pane="${line%%|*}"; line="${line#*|}"
        alt="${line%%|*}";  line="${line#*|}"
        tty="${line%%|*}";  title="${line#*|}"
        case "$title" in
            "$MARKER"*) [ "$alt" = "0" ] && [ -w "$tty" ] && printf '\033]2;%s\033\\' "$(hostname -s 2>/dev/null || hostname)" > "$tty" ;;
        esac
    done
}

# -t <session> resolves to the active pane of that session's current window
decide() {
    local info hold remote alt cmd title c
    info=$(tmux display-message -p -t "$session" '#{@remote_hold}|#{@remote}|#{alternate_on}|#{pane_current_command}|#{pane_title}' 2>/dev/null)
    hold="${info%%|*}";   info="${info#*|}"
    remote="${info%%|*}"; info="${info#*|}"
    alt="${info%%|*}";    info="${info#*|}"
    cmd="${info%%|*}";    title="${info#*|}"
    case "$hold" in
        on)  echo on;  return ;;
        off) echo off; return ;;
    esac
    [ "$remote" = "1" ] && { echo on; return; }
    if [ "$alt" = "1" ]; then
        case "$title" in
            "$MARKER"*)
                for c in $REMOTE_CLIENTS; do
                    [ "$cmd" = "$c" ] && { echo on; return; }
                done
                ;;
        esac
    fi
    echo off
}

case "$mode" in
    auto) ;;
    window-changed)
        # an F12 override belongs to the visit, not to the window
        for w in $(tmux list-windows -t "$session" -F '#{window_id}' 2>/dev/null); do
            tmux set -w -u -t "$w" @remote_hold 2>/dev/null
        done
        ;;
    toggle-on)  tmux set -w -t "$session" @remote_hold on ;;
    toggle-off) tmux set -w -t "$session" @remote_hold off ;;
    on)  apply_on;  exit 0 ;;
    off) apply_off; exit 0 ;;
    *)
        echo "usage: remote-mode.sh auto|window-changed|toggle-on|toggle-off [target]" >&2
        exit 1
        ;;
esac

sweep_stale_markers
if [ "$(decide)" = "on" ]; then apply_on; else apply_off; fi
exit 0
