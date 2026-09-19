#!/usr/bin/env bash
# Switch the local tmux between "local" and "remote" key handling.
#
#   remote-mode.sh on   [target]   prefix off — every key goes to the inner (remote) tmux
#   remote-mode.sh off  [target]   prefix back on
#   remote-mode.sh auto [target]   on when the session's current window is a
#                                  remote one (@remote set by ssh-remote.sh)
#
# target is anything tmux accepts for -t (session id, pane id); it is resolved
# to its session, because prefix and key-table are session options.
mode="${1:-auto}"
target="${2:-${TMUX_PANE:-}}"

if [ -n "$target" ]; then
    session=$(tmux display-message -p -t "$target" '#{session_id}' 2>/dev/null)
else
    session=$(tmux display-message -p '#{session_id}' 2>/dev/null)
fi
[ -z "$session" ] && exit 0

if [ "$mode" = "auto" ]; then
    # -t <session> resolves to that session's current window
    if [ "$(tmux display-message -p -t "$session" '#{@remote}' 2>/dev/null)" = "1" ]; then
        mode="on"
    else
        mode="off"
    fi
fi

case "$mode" in
    on)
        tmux set -t "$session" prefix None \; \
             set -t "$session" key-table off \; \
             set -t "$session" status-left '#[bg=colour1,fg=colour15,bold]  REMOTE #[default] ' \; \
             if -F -t "$session" '#{pane_in_mode}' 'send-keys -X cancel' \; \
             refresh-client -S >/dev/null 2>&1
        ;;
    off)
        tmux set -u -t "$session" prefix \; \
             set -u -t "$session" key-table \; \
             set -u -t "$session" status-left \; \
             refresh-client -S >/dev/null 2>&1
        ;;
    *)
        echo "usage: remote-mode.sh on|off|auto [target]" >&2
        exit 1
        ;;
esac
exit 0
