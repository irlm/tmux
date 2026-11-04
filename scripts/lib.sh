#!/usr/bin/env bash
# Shared runtime paths. All overrides are optional and useful for isolated tests.
TMUX_CONFIG_DIR="${TMUX_CONFIG_DIR:-$HOME/.config/tmux}"
TMUX_DATA_DIR="${TMUX_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/tmux}"
TMUX_CACHE_DIR="${TMUX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/tmux}"
TMUX_PROFILE="${TMUX_PROFILE:-desktop}"
# User-owned settings live outside the checkout, beside the saved theme.
TMUX_USER_DIR="${TMUX_THEME_DIR:-$HOME/.config/tmux-user}"

# Which multiplexer started this script. Herdr strips the TMUX marker from
# its panes and sets HERDR_ENV, so the two never look alike. "none" covers a
# plain shell, cron, or a test that runs a script by hand.
wb_backend() {
    if [ -n "${TMUX:-}" ]; then printf 'tmux\n'
    elif [ "${HERDR_ENV:-}" = 1 ]; then printf 'herdr\n'
    else printf 'none\n'; fi
}

# Option lookup. Under tmux the value is the @option; everywhere else it is a
# line "name=value" in ~/.config/tmux-user/options.env (the @ dropped), which
# is also what Herdr reads. The second argument is the default.
tmux_option() {
    local name=${1#@} value=""
    if [ "$(wb_backend)" = tmux ]; then
        value=$(tmux show-option -gqv "@$name" 2>/dev/null) || value=""
    elif [ -r "$TMUX_USER_DIR/options.env" ]; then
        value=$(awk -F '=' -v key="$name" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$TMUX_USER_DIR/options.env")
    fi
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
