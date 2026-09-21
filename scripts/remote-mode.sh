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
#   - its window was opened by ssh-remote.sh (@remote), or
#   - a full-screen program is running in it and the terminal title carries the
#     marker a server-side tmux sets (see "Remote marker" in tmux.conf) — which
#     is how an ssh typed by hand, mosh, or a jump host is picked up too.
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

apply_on() {
    tmux set -t "$session" prefix None \; \
         set -t "$session" key-table off \; \
         set -t "$session" status-left '#[bg=colour1,fg=colour15,bold]  REMOTE #[default] ' \; \
         if -F -t "$session" '#{pane_in_mode}' 'send-keys -X cancel' \; \
         refresh-client -S >/dev/null 2>&1
}

apply_off() {
    tmux set -u -t "$session" prefix \; \
         set -u -t "$session" key-table \; \
         set -u -t "$session" status-left \; \
         refresh-client -S >/dev/null 2>&1
}

# -t <session> resolves to the active pane of that session's current window
decide() {
    local info hold remote alt title
    info=$(tmux display-message -p -t "$session" '#{@remote_hold}|#{@remote}|#{alternate_on}|#{pane_title}' 2>/dev/null)
    hold="${info%%|*}";  info="${info#*|}"
    remote="${info%%|*}"; info="${info#*|}"
    alt="${info%%|*}";   title="${info#*|}"
    case "$hold" in
        on)  echo on;  return ;;
        off) echo off; return ;;
    esac
    [ "$remote" = "1" ] && { echo on; return; }
    if [ "$alt" = "1" ]; then
        case "$title" in "$MARKER"*) echo on; return ;; esac
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

if [ "$(decide)" = "on" ]; then apply_on; else apply_off; fi
exit 0
