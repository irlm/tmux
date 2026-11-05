#!/usr/bin/env bash
# Read-only diagnostics; any temporary parser server uses a separate socket.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
failures=0
fail() { printf '  FAIL: %s\n' "$*"; failures=$((failures + 1)); }
warn() { printf '  WARN: %s\n' "$*"; }
profile=${TMUX_PROFILE:-desktop}
! wb_server_install || profile=server
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
if [ "$profile" != server ]; then
    case "$(uname -s)" in
        Darwin) ls "$HOME/Library/Fonts"/JetBrainsMono*Nerd* /Library/Fonts/JetBrainsMono*Nerd* >/dev/null 2>&1 || brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 || warn 'JetBrains Mono Nerd Font missing — run install.sh (status icons need it).' ;;
        *) if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v fc-list >/dev/null 2>&1 && ! grep -qi microsoft /proc/version 2>/dev/null; then
               fc-list | grep -qi 'JetBrainsMono Nerd' || warn 'JetBrains Mono Nerd Font missing — run install.sh (status icons need it).'
           fi ;;
    esac
fi
# A managed shell file plus the older inline block in the rc file runs the
# banner and the prompt twice.
for _rc in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc"; do
    case "$_rc" in *.zshrc) _managed=shell.zsh ;; *) _managed=shell.bash ;; esac
    [ -f "$HOME/.config/tmux-user/$_managed" ] && [ -f "$_rc" ] || continue
    _lines=$(grep -nE 'fastfetch -l small|oh-my-posh init|zoxide init' "$_rc" | cut -d: -f1 | tr '\n' ' ')
    [ -z "$_lines" ] || warn "$_rc line(s) ${_lines% }: older inline shell setup; the managed shell file provides it now, so remove those lines (banner and prompt load twice)."
done
unset _rc _lines _managed
if command -v herdr >/dev/null 2>&1 && [ -f "$TMUX_CONFIG_DIR/herdr/config.toml" ]; then
    if _message=$(herdr_too_old); then fail "$_message (the rendered config is rejected and C-a stays unbound in Herdr)"; fi
    unset _message
    _linked=$(herdr plugin list --json 2>/dev/null | python3 -c '
import json, sys
try:
    plugins = json.load(sys.stdin)["result"]["plugins"]
except Exception:
    sys.exit(0)
print(next((p.get("plugin_root", "") for p in plugins if p.get("plugin_id") == "irlm.workbench"), ""), end="")')
    if [ -n "$_linked" ] && [ "$_linked" != "$TMUX_USER_DIR/herdr-plugin" ]; then
        fail "Herdr plugin irlm.workbench is linked from $_linked, not $TMUX_USER_DIR/herdr-plugin — run scripts/herdr-config.sh."
    elif [ -n "$_linked" ] && [ ! -f "$_linked/herdr-plugin.toml" ]; then
        fail "Herdr plugin manifest missing in $_linked — run scripts/herdr-config.sh."
    fi
    unset _linked
fi
if command -v hx >/dev/null 2>&1 && [ -f "$TMUX_CONFIG_DIR/helix/config.toml" ]; then
    helix_config="${HELIX_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/helix}/config.toml"
    if [ -L "$helix_config" ] && [ "$(readlink "$helix_config")" = "$TMUX_CONFIG_DIR/helix/config.toml" ]; then
        echo '  Helix: config linked from this repo.'
    else
        fail "Helix config not linked from $TMUX_CONFIG_DIR/helix — run update.sh."
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
if command -v herdr >/dev/null 2>&1; then
    herdr_config="${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}"
    if head -3 "$herdr_config" 2>/dev/null | grep -qE 'Generated by irlm/(workbench|tmux)'; then
        report=$(herdr config check 2>&1) || fail "Herdr config rejected: $report"
        case "$report" in *"issues found"*) fail "Herdr config has issues: $(printf '%s' "$report" | tail -n +2 | tr '\n' ' ')" ;; esac
        # plain grep, not -q: under pipefail an early exit would look like no match
        herdr plugin list 2>/dev/null | grep 'irlm.workbench' >/dev/null || fail 'Herdr plugin irlm.workbench not linked — run scripts/herdr-config.sh.'
        for agent in claude codex; do
            command -v "$agent" >/dev/null 2>&1 || continue
            herdr integration status 2>/dev/null | grep -E "^$agent: current" >/dev/null || fail "Herdr integration for $agent missing or outdated — run herdr integration install $agent."
        done
        echo '  Herdr: managed config, plugin and integrations checked.'
    else
        echo '  Herdr: installed but not configured from this repo (run scripts/herdr-config.sh).'
    fi
fi
if [ "$failures" -gt 0 ]; then printf 'Health check: %s failure(s).\n' "$failures"; exit 1; fi
printf 'Health check: required tools and configuration passed.\n'
