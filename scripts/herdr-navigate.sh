#!/usr/bin/env bash
# ctrl+h/j/k/l under Herdr, the way vim-tmux-navigator does it under tmux:
# when the active pane runs Neovim the key goes to the editor (which moves
# between its own windows and calls `herdr pane focus` at an edge), and
# otherwise Herdr moves the focus itself.
#
#   herdr-navigate.sh left|down|up|right
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
direction=${1:-}
case "$direction" in
    left) key=h ;; down) key=j ;; up) key=k ;; right) key=l ;;
    *) printf 'Usage: herdr-navigate.sh left|down|up|right\n' >&2; exit 2 ;;
esac
pane=$(herdr_active_pane)
[ -n "$pane" ] || exit 0
front=$(herdr pane process-info --pane "$pane" 2>/dev/null | python3 -c '
import json, sys
try:
    procs = json.load(sys.stdin)["result"]["process_info"]["foreground_processes"]
except Exception:
    sys.exit(0)
print(procs[-1].get("name", "") if procs else "", end="")')
case "$front" in
    vim|nvim|vi|view|nvim-*|*vim) herdr pane send-keys "$pane" "ctrl+$key" >/dev/null ;;
    *) herdr pane focus --direction "$direction" --pane "$pane" >/dev/null 2>&1 ;;
esac
