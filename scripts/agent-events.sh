#!/usr/bin/env bash
# Herdr plugin event hook: runs on every agent state change
# (pane.agent_status_changed). It keeps a journal of the changes, which the
# agents picker (C-a w) uses for "how long in this state", and reports the
# size of the uncommitted work in that pane's repository as the $changes
# token of its workspace row in the sidebar ("3 files +40 -12").
#
#   agent-events.sh                 from Herdr, with HERDR_PLUGIN_EVENT_JSON
#   agent-events.sh --refresh PANE  recompute the token for one pane by hand
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
JOURNAL="$TMUX_DATA_DIR/agent-journal.tsv"

changes_in() {   # "N files +a -d", "clean", or "" outside a repository
    local dir=$1 stat untracked files added removed
    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    stat=$(git -C "$dir" diff HEAD --shortstat 2>/dev/null)
    untracked=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    files=$(printf '%s' "$stat" | sed -n 's/^ *\([0-9]*\) file.*/\1/p'); files=$(( ${files:-0} + untracked ))
    added=$(printf '%s' "$stat" | sed -n 's/.* \([0-9]*\) insertion.*/\1/p')
    removed=$(printf '%s' "$stat" | sed -n 's/.* \([0-9]*\) deletion.*/\1/p')
    if [ "$files" -eq 0 ]; then echo clean; return; fi
    printf '%s file%s +%s -%s\n' "$files" "$([ "$files" -ne 1 ] && echo s)" "${added:-0}" "${removed:-0}"
}

# Fill in workspace and cwd from the pane when the event did not carry them.
resolve_pane() {
    local pane=$1
    if [ -z "$cwd" ] || [ -z "$workspace" ]; then
        read -r workspace cwd <<< "$(herdr pane get "$pane" 2>/dev/null | python3 -c '
import json, sys
try:
    pane = json.load(sys.stdin)["result"]["pane"]
except Exception:
    sys.exit(0)
print(pane.get("workspace_id", ""), pane.get("foreground_cwd") or pane.get("cwd") or "")')"
    fi
}

report() {   # pane -> workspace token
    local pane=$1 changes
    resolve_pane "$pane"
    [ -n "$workspace" ] && [ -n "$cwd" ] || return 0
    changes=$(changes_in "$cwd")
    if [ -n "$changes" ]; then
        herdr workspace report-metadata "$workspace" --source workbench --token "changes=$changes" >/dev/null 2>&1
    else
        herdr workspace report-metadata "$workspace" --source workbench --clear-token changes >/dev/null 2>&1
    fi
}

workspace=""; cwd=""
case "${1:-}" in
    --refresh) report "${2:?pane id}"; exit ;;
esac
[ -n "${HERDR_PLUGIN_EVENT_JSON:-}" ] || exit 0
read -r pane workspace status agent cwd <<< "$(printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | python3 -c '
import json, sys
event = json.load(sys.stdin)
# The payload nests differently between versions; look at every level.
def find(key):
    stack = [event]
    while stack:
        node = stack.pop(0)
        if isinstance(node, dict):
            if key in node and isinstance(node[key], (str, int)):
                return str(node[key])
            stack.extend(node.values())
    return ""
print(find("pane_id") or "-", find("workspace_id") or "-", find("agent_status") or find("status") or "-",
      find("agent") or "-", find("foreground_cwd") or find("cwd") or "-")')"
[ -n "$pane" ] && [ "$pane" != - ] || exit 0
for v in workspace status agent cwd; do [ "${!v}" != - ] || printf -v "$v" '%s' ''; done
resolve_pane "$pane"
if private_dir "$TMUX_DATA_DIR" 2>/dev/null; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$workspace" "$pane" "$agent" "$status" >> "$JOURNAL"
    # Keep the journal short: the last 2000 changes are more than a week.
    if [ "$(wc -l < "$JOURNAL")" -gt 3000 ]; then tail -2000 "$JOURNAL" > "$JOURNAL.tmp" && mv "$JOURNAL.tmp" "$JOURNAL"; fi
fi
report "$pane"
