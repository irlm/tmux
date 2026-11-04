#!/usr/bin/env bash
# Shared runtime paths. All overrides are optional and useful for isolated tests.
TMUX_CONFIG_DIR="${TMUX_CONFIG_DIR:-$HOME/.config/tmux}"
TMUX_DATA_DIR="${TMUX_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/tmux}"
TMUX_CACHE_DIR="${TMUX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/tmux}"
TMUX_PROFILE="${TMUX_PROFILE:-desktop}"
# User-owned settings live outside the checkout, beside the saved theme.
TMUX_USER_DIR="${TMUX_THEME_DIR:-$HOME/.config/tmux-user}"

# Windows (Git Bash) installs Python as python.exe only.
if ! command -v python3 >/dev/null 2>&1 && command -v python >/dev/null 2>&1; then
    python3() { python "$@"; }
fi

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
    if [ "$(wb_backend)" != herdr ]; then
        # Also from a plain shell or a hook: a reachable tmux server answers.
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
    printf '\nPress any key to close...'
    IFS= read -rsn1 _ || true
}

# tools.tsv scopes: all (every profile), desktop (not servers), nvim (only
# when the optional Neovim config is checked out on a desktop).
tool_scope_filter() {
    local profile=${1:-desktop} nvim=0
    [ "$profile" = server ] || [ ! -f "${NVIM_CONFIG_DIR:-$HOME/.config/nvim}/init.lua" ] || nvim=1
    printf -- '-v profile=%s -v nvim=%s' "$profile" "$nvim"
}

managed_tools() {
    # shellcheck disable=SC2046
    awk -F '\t' $(tool_scope_filter "$1") 'NR > 1 && ($4 == "all" || (profile != "server" && $4 == "desktop") || (nvim && $4 == "nvim")) {print $1}' "$TMUX_CONFIG_DIR/tools.tsv"
}

brew_tools() {
    # shellcheck disable=SC2046
    awk -F '\t' $(tool_scope_filter "$1") 'NR > 1 && $2 != "-" && ($4 == "all" || (profile != "server" && $4 == "desktop") || (nvim && $4 == "nvim")) {print $2}' "$TMUX_CONFIG_DIR/tools.tsv"
}

# Herdr CLI. Inside a Herdr pane HERDR_BIN_PATH names the binary that owns
# the session; WB_HERDR_SESSION lets tests aim every call at a named session.
# `command` skips this function when the binary is found by name; without
# it a shell outside Herdr (no HERDR_BIN_PATH) recursed until it crashed.
herdr() {
    if [ -n "${WB_HERDR_SESSION:-}" ]; then
        command "${HERDR_BIN_PATH:-herdr}" --session "$WB_HERDR_SESSION" "$@"
    else
        command "${HERDR_BIN_PATH:-herdr}" "$@"
    fi
}

# The pane a popup or key command was opened over. Herdr tells custom
# commands through HERDR_ACTIVE_PANE_ID and plugin panes through the context
# JSON; a plain pane knows itself; the last resort is the focused pane.
herdr_active_pane() {
    if [ -n "${HERDR_ACTIVE_PANE_ID:-}" ]; then printf '%s' "$HERDR_ACTIVE_PANE_ID"; return; fi
    if [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
        local pane
        pane=$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | python3 -c '
import json, sys
context = json.load(sys.stdin)
for key in ("active_pane_id", "focused_pane_id", "pane_id"):
    if context.get(key): print(context[key], end=""); break
else:
    pane = context.get("pane") or context.get("focused_pane") or {}
    print(pane.get("pane_id", "") if isinstance(pane, dict) else pane, end="")' 2>/dev/null)
        [ -z "$pane" ] || { printf '%s' "$pane"; return; }
    fi
    if [ -n "${HERDR_PANE_ID:-}" ]; then printf '%s' "$HERDR_PANE_ID"; return; fi
    herdr pane list 2>/dev/null | python3 -c '
import json, sys
try:
    panes = json.load(sys.stdin)["result"]["panes"]
except Exception:
    sys.exit(1)
print(next((p["pane_id"] for p in panes if p.get("focused")), ""), end="")'
}

# Does a registry row with this hosts field apply to the running backend?
# Fields: all, tmux, herdr. A plain shell counts as tmux for the help text.
wb_host_match() {
    local hosts=${1:-all} backend
    backend=$(wb_backend); [ "$backend" != none ] || backend=tmux
    [ "$hosts" = all ] || [ "$hosts" = "$backend" ]
}
