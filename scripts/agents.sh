#!/usr/bin/env bash
# Every coding agent on this machine in one list: state, workspace, what it
# is on, how long since it changed state, where it runs. Enter jumps to it.
# Under Herdr the rows come from `herdr agent list` and the ages from the
# journal agent-events.sh keeps; under tmux from the panes running an agent.
#
#   agents.sh          the picker (C-a w)
#   agents.sh --list   the rows only, for scripts
#
# In the picker: Enter focus · C-r read the last 400 lines · C-s send a
# prompt · C-d review the changes in that agent's directory · Esc close.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
JOURNAL="$TMUX_DATA_DIR/agent-journal.tsv"
backend=$(wb_backend)

# One row per agent: pane id, then the columns shown.
rows() {
    case "$backend" in
        herdr)
            { herdr agent list 2>/dev/null; echo; herdr workspace list 2>/dev/null; } | JOURNAL="$JOURNAL" python3 -c '
import json, os, sys, time
chunks = sys.stdin.read().split("\n\n", 1)
try:
    agents = json.loads(chunks[0])["result"]["agents"]
except Exception:
    agents = []
labels = {}
try:
    for ws in json.loads(chunks[1])["result"]["workspaces"]:
        labels[ws["workspace_id"]] = ws.get("label") or ws["workspace_id"]
except Exception:
    pass
last = {}
try:
    for line in open(os.environ["JOURNAL"], encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 5:
            last[parts[2]] = (float(parts[0]), parts[4])
except (OSError, ValueError):
    pass
ICON = {"working": "◐", "blocked": "▲", "done": "✔", "idle": "○", "unknown": "?"}
ORDER = {"blocked": 0, "done": 1, "working": 2, "idle": 3, "unknown": 4}
home = os.path.expanduser("~")
def age(pane, state):
    stamp = last.get(pane)
    if not stamp or stamp[1] != state:
        return ""
    seconds = int(time.time() - stamp[0])
    if seconds < 60: return f"{seconds}s"
    if seconds < 3600: return f"{seconds // 60}m"
    return f"{seconds // 3600}h{(seconds % 3600) // 60:02d}m"
agents.sort(key=lambda a: (ORDER.get(a.get("agent_status"), 9), a.get("workspace_id", ""), a.get("pane_id", "")))
for a in agents:
    state = a.get("agent_status", "unknown")
    where = labels.get(a.get("workspace_id"), a.get("workspace_id", "")) + "/" + a.get("tab_id", "").split(":")[-1]
    cwd = (a.get("cwd") or "").replace(home, "~", 1)
    title = a.get("terminal_title_stripped") or a.get("terminal_title") or ""
    icon = ICON.get(state, "?")
    print("\t".join([a["pane_id"], f"{icon} {state:<8}", where, a.get("agent", ""), age(a["pane_id"], state), title, cwd]))
' ;;
        tmux)
            tmux list-panes -a -F $'#{pane_id}\t#{session_name}/#{window_index}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}' 2>/dev/null |
            awk -F '\t' '$3 ~ /^(claude|codex|node)$/ || $3 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ {
                cwd = $5; sub("^" ENVIRON["HOME"], "~", cwd)
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, "? running ", $2, $3, "", $4, cwd }' ;;
        *) return 1 ;;
    esac
}

preview() {
    case "$backend" in
        herdr) herdr pane read "$1" --source visible 2>/dev/null ;;
        tmux) tmux capture-pane -p -t "$1" 2>/dev/null ;;
    esac
}

focus() {
    case "$backend" in
        herdr) herdr agent focus "$1" >/dev/null ;;
        tmux) tmux switch-client -t "$(tmux display-message -p -t "$1" '#{session_name}')" 2>/dev/null
              tmux select-window -t "$(tmux display-message -p -t "$1" '#{session_name}:#{window_index}')"
              tmux select-pane -t "$1" ;;
    esac
}

send_prompt() {
    local pane=$1 text
    printf 'Prompt for %s (Enter sends, empty cancels): ' "$pane"; IFS= read -r text || return 0
    [ -n "$text" ] || return 0
    case "$backend" in
        herdr) herdr agent prompt "$pane" "$text" >/dev/null && echo 'Sent.' ;;
        tmux) printf '%s' "$text" | tmux load-buffer -b wb-agent-prompt - && tmux paste-buffer -p -d -b wb-agent-prompt -t "$pane" && tmux send-keys -t "$pane" Enter && echo 'Sent.' ;;
    esac
    sleep 0.6
}

case "${1:-}" in
    --list) rows; exit ;;
    --preview) preview "$2"; exit ;;
esac
[ "$backend" != none ] || { echo 'Not inside Herdr or tmux.' >&2; exit 1; }
command -v fzf >/dev/null 2>&1 || { "$SCRIPT_DIR/popup.sh" fzf; exit $?; }
while :; do
    list=$(rows)
    if [ -z "$list" ]; then echo 'No coding agent is running here (Claude Code, Codex, ...).'; pause_close; exit 0; fi
    picked=$(printf '%s\n' "$list" | fzf --delimiter=$'\t' --with-nth=2.. --tabstop=1 --no-sort --ansi \
        --prompt='Agent > ' --expect=ctrl-r,ctrl-s,ctrl-d \
        --header='Enter jump · C-r read · C-s prompt · C-d review its changes' \
        --preview "bash $(printf '%q' "$0") --preview {1}" --preview-window='right,55%,border-left,follow') || exit 0
    key=""; line=$picked
    case "$picked" in *$'\n'*) key=${picked%%$'\n'*}; line=${picked#*$'\n'} ;; esac
    pane=${line%%$'\t'*}
    [ -n "$pane" ] || exit 0
    case "$key" in
        ctrl-r)
            case "$backend" in
                herdr) herdr agent read "$pane" --source recent-unwrapped --lines 400 2>/dev/null | less -KR ;;
                tmux) tmux capture-pane -pJS -400 -t "$pane" | less -KR ;;
            esac ;;
        ctrl-s) send_prompt "$pane" ;;
        ctrl-d)
            cwd=$(printf '%s\n' "$line" | awk -F '\t' '{print $7}')
            "$SCRIPT_DIR/review.sh" "${cwd/#\~/$HOME}" ;;
        *) focus "$pane"; exit 0 ;;
    esac
done
