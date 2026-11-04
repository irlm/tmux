#!/usr/bin/env bash
# Put the text on stdin into the coding agent's input, without pressing Enter,
# so you can add a word before sending. Helix: `\a` on a selection. Shell:
# `git diff | agent-send.sh`. The agent is the first Claude or Codex pane in
# the current workspace (Herdr) or session (tmux).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
text=$(cat)
[ -n "$text" ] || exit 0
case "$(wb_backend)" in
    herdr)
        pane=$(herdr agent list 2>/dev/null | python3 -c '
import json, os, sys
agents = json.load(sys.stdin)["result"]["agents"]
here = os.environ.get("HERDR_WORKSPACE_ID") or os.environ.get("HERDR_ACTIVE_WORKSPACE_ID")
agents.sort(key=lambda a: (a.get("workspace_id") != here, a.get("pane_id")))
print(agents[0]["pane_id"] if agents else "", end="")')
        [ -n "$pane" ] || { echo 'No agent pane in Herdr.' >&2; exit 1; }
        herdr pane send-text "$pane" "$text" >/dev/null && echo "Sent to $pane" ;;
    tmux)
        pane=$(tmux list-panes -s -F '#{pane_id} #{pane_current_command}' 2>/dev/null | awk '$2 ~ /^(claude|codex|node)$/ || $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ {print $1; exit}')
        [ -n "$pane" ] || { echo 'No agent pane in this tmux session.' >&2; exit 1; }
        tmux send-keys -t "$pane" -l -- "$text" && echo "Sent to $pane" ;;
    *) echo 'Not inside Herdr or tmux.' >&2; exit 1 ;;
esac
