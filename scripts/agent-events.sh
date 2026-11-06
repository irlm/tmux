#!/usr/bin/env bash
# Herdr plugin event hook: runs on every agent state change
# (pane.agent_status_changed). It keeps a journal of the changes, which the
# agents picker (C-a w) uses for "how long in this state", and reports the
# size of the uncommitted work in that pane's repository as the $changes
# token of its workspace row in the sidebar ("3 files +40 -12"), and the
# context size of a Claude Code pane as its $ctx token ("ctx 240k").
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

# What the pane knows and the event may not carry: workspace, agent, the
# agent's own session id, cwd (last, since it may hold spaces).
resolve_pane() {
    local pane=$1 p_workspace p_agent p_session p_cwd
    read -r p_workspace p_agent p_session p_cwd <<< "$(herdr pane get "$pane" 2>/dev/null | python3 -c '
import json, sys
try:
    pane = json.load(sys.stdin)["result"]["pane"]
except Exception:
    sys.exit(0)
native = pane.get("agent_session") or {}
print(pane.get("workspace_id") or "-", pane.get("agent") or native.get("agent") or "-", native.get("value") or "-",
      pane.get("foreground_cwd") or pane.get("cwd") or "")')"
    [ -n "$workspace" ] || { [ "${p_workspace:--}" = - ] || workspace=$p_workspace; }
    [ -n "$agent" ] || { [ "${p_agent:--}" = - ] || agent=$p_agent; }
    [ "${p_session:--}" = - ] || session=$p_session
    [ -n "$cwd" ] || cwd=$p_cwd
}

# Context size of a Claude Code session after its last turn, in thousands of
# tokens: what the next turn re-reads before it does anything. Read from the
# tail of the transcript, so it costs a file read and no model.
context_k() {
    local id=$1 dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" file found=""
    case "$id" in ''|*[!A-Za-z0-9-]*) return 0 ;; esac
    for file in "$dir"/*/"$id".jsonl; do [ -f "$file" ] && { found=$file; break; }; done
    [ -n "$found" ] || return 0
    tail -c 600000 "$found" | python3 -c '
import json, sys
tokens = None
for line in sys.stdin:
    try:
        entry = json.loads(line)
    except ValueError:
        continue
    message = entry.get("message")
    if entry.get("type") != "assistant" or entry.get("isSidechain") or not isinstance(message, dict):
        continue
    usage = message.get("usage") or {}
    total = sum(int(usage.get(key) or 0) for key in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    if total:
        tokens = total
if tokens:
    print(max(1, round(tokens / 1000)), end="")'
}

# The pane token: $ctx under the warning size (ctx_warn_k in options.env,
# thousands of tokens, default 100, the size past which a new session per
# task pays off), $ctx_big from there on, which the sidebar paints.
report_context() {
    local pane=$1 size warn
    [ "$agent" = claude ] || return 0
    size=$(context_k "$session"); [ -n "$size" ] || return 0
    warn=$(tmux_option @ctx_warn_k 100); case "$warn" in ''|*[!0-9]*) warn=100 ;; esac
    if [ "$size" -ge "$warn" ]; then
        herdr pane report-metadata "$pane" --source workbench --token "ctx_big=ctx ${size}k" --clear-token ctx >/dev/null 2>&1
    else
        herdr pane report-metadata "$pane" --source workbench --token "ctx=ctx ${size}k" --clear-token ctx_big >/dev/null 2>&1
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
    report_context "$pane"
}

workspace=""; cwd=""; agent=""; session=""
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
