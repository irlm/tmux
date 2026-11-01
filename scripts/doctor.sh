#!/usr/bin/env bash
# Read-only diagnostics; any temporary parser server uses a separate socket.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
failures=0
fail() { printf '  FAIL: %s\n' "$*"; failures=$((failures + 1)); }
profile=${TMUX_PROFILE:-desktop}
[ ! -f "${NVIM_CONFIG_DIR:-$HOME/.config/nvim}/.server" ] || profile=server
printf 'Health check (%s)\n' "$profile"
[ -r "$TMUX_CONFIG_DIR/tools.tsv" ] || fail "Tool manifest missing — update or reinstall $TMUX_CONFIG_DIR."
while IFS= read -r tool; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool missing — run $TMUX_CONFIG_DIR/update.sh --fix"
done < <(managed_tools "$profile")
if command -v tmux >/dev/null 2>&1; then
    version=$(tmux -V | sed -E 's/^[^0-9]*([0-9]+)\.([0-9]+).*/\1 \2/')
    read -r major minor <<< "$version"
    if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] ||
       [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 2 ]; }; then
        fail 'tmux 3.2 or newer is required for popups; upgrade tmux.'
    fi
    config="$TMUX_CONFIG_DIR/tmux.conf"
    if [ ! -f "$config" ]; then
        fail "Config missing: $config — run install.sh."
    else
        scratch=$(mktemp -d)
        trap 'tmux -S "$scratch/socket" kill-server >/dev/null 2>&1 || true; rm -rf -- "$scratch"' EXIT
        if tmux -S "$scratch/socket" -f /dev/null new-session -d -s doctor 'sleep 30' >/dev/null 2>&1; then
            if ! tmux -S "$scratch/socket" source-file -n "$config"; then fail 'tmux config has syntax errors.'; fi
        else
            fail 'Unable to start an isolated config parser; check tmux socket permissions.'
        fi
        while IFS= read -r plugin; do
            [ -d "$TMUX_CONFIG_DIR/plugins/${plugin##*/}" ] || fail "Plugin $plugin missing — press C-a I."
        done < <(sed -n "s/^set -g @plugin '\([^']*\)'.*/\1/p" "$config")
    fi
    if [ -n "${TMUX:-}" ]; then
        clipboard=$(tmux display-message -p '#{client_termfeatures}' 2>/dev/null) || clipboard=""
        case "$clipboard" in *clipboard*) echo '  Clipboard: terminal advertises clipboard support.' ;;
            *) echo '  Clipboard: run a copy/paste check in your terminal; OSC 52 cannot be verified without an attached capable client.' ;; esac
    else
        echo '  Clipboard: verify OSC 52 after attaching tmux (no active client).'
    fi
fi
if command -v infocmp >/dev/null 2>&1 && ! infocmp tmux-256color >/dev/null 2>&1; then
    fail 'tmux-256color terminfo is missing — install your tmux/terminfo package.'
fi
if [ "$profile" != server ] && command -v gh >/dev/null 2>&1; then
    if ! gh extension list 2>/dev/null | grep -F 'dlvhdr/gh-dash' >/dev/null; then
        fail 'gh-dash missing — run gh extension install dlvhdr/gh-dash.'
    fi
fi
if [ "$failures" -gt 0 ]; then printf 'Health check: %s failure(s).\n' "$failures"; exit 1; fi
printf 'Health check: required tools and configuration passed.\n'
