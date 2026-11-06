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
# Python reads and writes UTF-8 in every script. On Windows a pipe or a file
# is cp1252 by default: Herdr's JSON (UTF-8, with pane titles in it) does not
# always decode, and a state icon cannot be written to a picker at all.
export PYTHONUTF8=1

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

# A server install writes ~/.config/tmux-user/profile = server (older installs
# only had Neovim's .server marker, which still counts).
wb_server_install() {
    [ "$(cat "$TMUX_USER_DIR/profile" 2>/dev/null)" = server ] || [ -f "${NVIM_CONFIG_DIR:-$HOME/.config/nvim}/.server" ]
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

# The oldest Herdr this configuration renders for (sidebar rows, worktrees,
# plugin events). An older binary rejects the config, which would leave
# Herdr on its default ctrl+b prefix.
WB_HERDR_MIN_VERSION=0.9.5
herdr_version() { command "${HERDR_BIN_PATH:-herdr}" --version 2>/dev/null | sed -n 's/^herdr \([0-9][0-9.]*\).*/\1/p' | head -1; }
# version_at_least 0.9.5 0.9.10 -> true when the second is not older.
version_at_least() {
    local want=$1 have=$2 a b
    [ -n "$have" ] || return 0   # unknown (a test stub): do not block
    IFS=. read -r a1 a2 a3 <<< "$want"; IFS=. read -r b1 b2 b3 <<< "$have"
    for pair in "${b1:-0}:${a1:-0}" "${b2:-0}:${a2:-0}" "${b3:-0}:${a3:-0}"; do
        b=${pair%%:*}; a=${pair#*:}
        [ "$b" -gt "$a" ] 2>/dev/null && return 0
        [ "$b" -lt "$a" ] 2>/dev/null && return 1
    done
    return 0
}
herdr_too_old() {   # prints the message, true when the installed Herdr is older than needed
    local have; have=$(herdr_version)
    version_at_least "$WB_HERDR_MIN_VERSION" "$have" && return 1
    printf 'Herdr %s is older than %s, which this configuration needs; run: herdr update\n' "$have" "$WB_HERDR_MIN_VERSION"
}

# Split beside a pane and run a command in the new pane once its shell is at
# the prompt (a fresh PowerShell takes a moment; text sent before that is
# lost). Prints the new pane id; on failure prints Herdr's own message.
herdr_split_run() {   # <pane> <right|down> <command>
    local pane=$1 direction=$2 command=$3 output new
    output=$(herdr pane split "$pane" --direction "$direction" --focus 2>&1) || { printf 'Could not split the pane: %s\n' "$output" >&2; return 1; }
    new=$(printf '%s' "$output" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"]["pane"]["pane_id"], end="")
except Exception: pass' 2>/dev/null)
    [ -n "$new" ] || { printf 'No pane id in the reply: %s\n' "$output" >&2; return 1; }
    herdr_run_when_ready "$new" "$command" || return 1
    printf '%s' "$new"
}

# Run a command in a pane once its shell is at the prompt.
herdr_run_when_ready() {   # <pane> <command>
    local pane=$1 command=$2 output
    for _ in $(seq 1 30); do
        if herdr pane process-info --pane "$pane" 2>/dev/null | python3 -c 'import json,sys,re
try: names = [p.get("name", "") for p in json.load(sys.stdin)["result"]["process_info"]["foreground_processes"]]
except Exception: sys.exit(1)
sys.exit(0 if names and all(re.match(r"^(-?)(zsh|bash|fish|sh|dash|nu|pwsh|powershell|cmd)(\.exe)?$", n) for n in names) else 1)'; then break; fi
        sleep 0.2
    done
    output=$(herdr pane run "$pane" "$command" 2>&1) || { printf 'Could not run "%s" in %s: %s\n' "$command" "$pane" "$output" >&2; return 1; }
}

# Does a registry row with this hosts field apply to the running backend?
# Fields: all, tmux, herdr. A plain shell counts as tmux for the help text.
wb_host_match() {
    local hosts=${1:-all} backend
    backend=$(wb_backend); [ "$backend" != none ] || backend=tmux
    [ "$hosts" = all ] || [ "$hosts" = "$backend" ]
}
