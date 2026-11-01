#!/usr/bin/env bash
# Shared runtime paths. All overrides are optional and useful for isolated tests.
TMUX_CONFIG_DIR="${TMUX_CONFIG_DIR:-$HOME/.config/tmux}"
TMUX_DATA_DIR="${TMUX_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/tmux}"
TMUX_CACHE_DIR="${TMUX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/tmux}"
TMUX_PROFILE="${TMUX_PROFILE:-desktop}"

tmux_option() {
    local value
    value=$(tmux show-option -gqv "$1" 2>/dev/null) || value=""
    printf '%s' "${value:-${2:-}}"
}

private_dir() {
    [ ! -L "$1" ] || return 1
    if [ -e "$1" ]; then [ -d "$1" ] && [ -O "$1" ] || return 1; fi
    (umask 077; mkdir -p "$1") || return 1
    chmod 700 "$1"
}

pause_close() {
    printf '\nPress Enter to close...'
    IFS= read -r _ || true
}

managed_tools() {
    awk -F '\t' -v profile="${1:-desktop}" 'NR > 1 && ($4 == "all" || profile != "server") {print $1}' "$TMUX_CONFIG_DIR/tools.tsv"
}

brew_tools() {
    awk -F '\t' -v profile="${1:-desktop}" 'NR > 1 && $2 != "-" && ($4 == "all" || profile != "server") {print $2}' "$TMUX_CONFIG_DIR/tools.tsv"
}
