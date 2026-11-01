#!/usr/bin/env bash
# Apply profiles before user-owned overrides; never fetch dependencies at startup.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
history=$(tmux show -gqv history-limit)
left=$(tmux show -gqv status-left-length)
right=$(tmux show -gqv status-right-length)
"$SCRIPT_DIR/actions.sh" bind
python3 "$SCRIPT_DIR/appearance.py" restore
for override in "$TMUX_CONFIG_DIR/local.conf" "${TMUX_LOCAL_CONF:-$HOME/.config/tmux-user/local.conf}"; do
    [ ! -f "$override" ] || tmux source-file "$override"
done
profile=$(tmux_option @profile auto)
if [ "$profile" = auto ]; then
    profile=desktop
    [ ! -f "${NVIM_CONFIG_DIR:-$HOME/.config/nvim}/.server" ] || profile=server
fi
limit=100000
case "$profile" in server|compact) limit=20000 ;; esac
limit=$(tmux_option @history_limit "$limit")
case "$limit" in ''|*[!0-9]*) limit=100000 ;; esac
if [ "$(tmux show -gqv history-limit)" = "$history" ]; then tmux set -g history-limit "$limit"; fi
if [ "$profile" = compact ]; then
    [ "$(tmux show -gqv status-left-length)" != "$left" ] || tmux set -g status-left-length 30
    [ "$(tmux show -gqv status-right-length)" != "$right" ] || tmux set -g status-right-length 40
fi

if [ "$(tmux_option @ascii off)" = on ]; then
    tmux set -g pane-border-lines simple \; set -g window-status-separator '|'
fi
