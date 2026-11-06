#!/usr/bin/env bash
# A worktree per task: pick an existing worktree of this repository, or type
# a branch name to create one, and land in it as its own Herdr workspace
# (grouped under this one) or tmux session. Both use the same directory
# layout, <worktree_dir>/<repo>/<branch>, so a checkout made under one
# multiplexer is listed under the other. C-a C-g.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
backend=$(wb_backend)
root=$(git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || { echo 'Not a Git repository.'; pause_close; exit 1; }
root=$(git -C "$root" worktree list --porcelain | sed -n '1s/^worktree //p')   # the main checkout
repo=$(basename "$root")
base=$(tmux_option @worktree_dir "$HOME/.herdr/worktrees"); base=${base/#\~/$HOME}
command -v fzf >/dev/null 2>&1 || { "$SCRIPT_DIR/popup.sh" fzf; exit $?; }
# The agent C-a starts in the worktree: worktree_agent in options.env.
agent_cmd=$(tmux_option @worktree_agent claude)
case "$agent_cmd" in ''|*[!A-Za-z0-9_.-]*) agent_cmd=claude ;; esac

existing() {   # path<TAB>branch   path (the main checkout first)
    git -C "$root" worktree list --porcelain | awk -v home="$HOME" '
        /^worktree / { path = substr($0, 10) }
        /^branch / { branch = substr($0, 8); sub("^refs/heads/", "", branch) }
        /^detached/ { branch = "(detached)" }
        /^$/ && path != "" { shown = path; sub("^" home, "~", shown); printf "%s\t%-28s %s\n", path, branch, shown; path = ""; branch = "" }
        END { if (path != "") { shown = path; sub("^" home, "~", shown); printf "%s\t%-28s %s\n", path, branch, shown } }'
}

picked=$(existing | fzf --delimiter=$'\t' --with-nth=2.. --tabstop=1 --no-sort --print-query \
    --prompt="Worktree of $repo > " --expect=ctrl-a \
    --header="Enter: open · C-a: open and start $agent_cmd there (a fresh session for the task) · type a new branch name to create it")
rc=$?
[ "$rc" -ne 130 ] || exit 0
# --print-query and --expect: the query, then the key (empty for Enter), then the row.
query=""; key=""; selection=""
{ IFS= read -r query; IFS= read -r key; IFS= read -r selection; } <<< "$picked" || true
selection=${selection%%$'\t'*}
if [ -n "$selection" ] && [ "$rc" -eq 0 ]; then
    path=$selection; branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$(basename "$path")")
else
    branch=$query
    [ -n "$branch" ] || exit 0
    case "$branch" in -*|*[[:space:]]*|*..*) echo "Not a branch name: $branch"; pause_close; exit 1 ;; esac
    path=""
fi

case "$backend" in
    herdr)
        if [ -n "$path" ] && [ "$path" != "$root" ]; then
            reply=$(herdr worktree open --cwd "$root" --path "$path" --focus 2>&1) || { printf '%s\n' "$reply"; pause_close; exit 1; }
        elif [ -n "$path" ]; then
            echo 'That is the main checkout; pick another worktree or type a branch name.'; pause_close; exit 0
        else
            reply=$(herdr worktree create --cwd "$root" --branch "$branch" --focus 2>&1) || { printf '%s\n' "$reply"; pause_close; exit 1; }
        fi
        if [ "$key" = ctrl-a ]; then
            # The reply names the new workspace's root pane; an already open
            # worktree only names its workspace, so ask for its first pane.
            pane=$(printf '%s' "$reply" | python3 -c 'import json,sys
try: r = json.load(sys.stdin)["result"]
except Exception: sys.exit(0)
print((r.get("root_pane") or {}).get("pane_id") or "", (r.get("workspace") or {}).get("workspace_id") or (r.get("worktree") or {}).get("open_workspace_id") or "")')
            workspace=${pane#* }; pane=${pane%% *}
            if [ -z "$pane" ] && [ -n "$workspace" ]; then
                pane=$(herdr pane list --workspace "$workspace" 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"]["panes"][0]["pane_id"], end="")
except Exception: pass')
            fi
            if [ -n "$pane" ]; then herdr_run_when_ready "$pane" "$agent_cmd" || { pause_close; exit 1; }
            else echo "Opened, but could not find its pane to start $agent_cmd."; pause_close; fi
        fi ;;
    tmux)
        if [ -z "$path" ]; then
            slug=$(printf '%s' "$branch" | tr '/' '-')
            path="$base/$repo/$slug"
            if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
                git -C "$root" worktree add "$path" "$branch" || { pause_close; exit 1; }
            else
                git -C "$root" worktree add -b "$branch" "$path" || { pause_close; exit 1; }
            fi
        fi
        session=$(printf '%s' "$repo-$(basename "$path")" | tr '.:' '__')
        if ! tmux has-session -t "=$session" 2>/dev/null; then
            tmux new-session -d -s "$session" -c "$path"
            # Only into a session made just now: an existing one may be busy.
            [ "$key" != ctrl-a ] || tmux send-keys -t "=$session:" "$agent_cmd" Enter
        fi
        tmux switch-client -t "=$session" ;;
    *) echo 'Not inside Herdr or tmux.' >&2; exit 1 ;;
esac
