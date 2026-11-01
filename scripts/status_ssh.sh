#!/usr/bin/env bash
# update <pane_pid> <session_id>: discover once and set this session's height.
# line <pane_pid>: render the cached discovery without another process scan.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
mode=${1:-line}; pid=${2:-}; session=${3:-}
case "$pid" in ''|*[!0-9]*) exit 0 ;; esac
private_dir "$TMUX_CACHE_DIR" || exit 0
cache="$TMUX_CACHE_DIR/ssh-$pid"
if [ "$mode" = line ]; then
    if [ -f "$cache" ]; then
        line=$(tail -n +2 "$cache")
        colors=$(tmux display-message -p '#{@theme_green}|#{@theme_blue}' 2>/dev/null) || colors=""
        IFS='|' read -r green blue <<< "$colors"
        green=${green:-colour2}; blue=${blue:-colour4}
        line=${line//'#[fg=colour2'/'#[fg='"$green"}
        line=${line//'#[fg=colour4'/'#[fg='"$blue"}
        printf '%s\n' "$line"
    fi
    exit 0
fi
case "$session" in \$[0-9]*) ;; *) exit 1 ;; esac
now=$(date +%s); sampled=0; line=""
if [ -f "$cache" ]; then
    IFS= read -r sampled < "$cache"
fi
if [[ "$sampled" =~ ^[0-9]+$ ]] && [ "$((now - sampled))" -ge 0 ] && [ "$((now - sampled))" -lt 5 ]; then
    line=$(tail -n +2 "$cache")
else
    line=$(python3 "$SCRIPT_DIR/ssh_info.py" "$pid") || line=""
    tmp=$(mktemp "$TMUX_CACHE_DIR/ssh.XXXXXX") || exit 0
    printf '%s\n%s\n' "$now" "$line" > "$tmp"
    mv -f -- "$tmp" "$cache"
fi
current=$(tmux show-option -A -t "$session" -qv status 2>/dev/null) || exit 0
desired=on
[ -z "$line" ] || desired=2
[ "$current" = "$desired" ] || tmux set-option -t "$session" status "$desired"
