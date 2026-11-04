#!/usr/bin/env bash
# Canonical paths identify projects; tmux IDs identify existing sessions.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
roots="${TMUX_PROJECT_ROOTS:-$(tmux_option @project_roots)}"
[ -n "$roots" ] || roots=$(printf '%s\n' "$HOME/projects" "$HOME/Projects" "$HOME/.config")
depth="${TMUX_PROJECT_DEPTH:-$(tmux_option @project_depth 6)}"
case "$depth" in ''|*[!0-9]*) depth=6 ;; esac
private_dir "$TMUX_DATA_DIR"
recent="$TMUX_DATA_DIR/recent-projects"

project_paths() {
    [ ! -f "$recent" ] || cat "$recent"
    while IFS= read -r root; do
        [ -d "$root" ] || continue
        find "$root" -maxdepth "$depth" \
            \( -type d \( -name plugins -o -name node_modules -o -name vendor -o -name target -o -name .cache \) -prune \) -o \
            \( -name .git \( -type d -o -type f \) -print -prune \) 2>/dev/null | sed 's|/\.git$||'
    done <<< "$roots"
}

# Under Herdr a workspace plays the session's part. Herdr does not record a
# workspace's directory, so the map written at creation time is consulted
# first and the live pane directories second.
backend=$(wb_backend)
workspace_map="$TMUX_DATA_DIR/herdr-workspaces"

herdr_workspaces() {  # id<TAB>label<TAB>directory of its first pane
    herdr api snapshot 2>/dev/null | python3 -c '
import json, sys
try:
    snapshot = json.load(sys.stdin)["result"]["snapshot"]
except Exception:
    sys.exit(0)
first = {}
for pane in snapshot.get("panes", []):
    first.setdefault(pane.get("workspace_id"), pane.get("cwd") or "")
for workspace in snapshot.get("workspaces", []):
    identifier = workspace.get("workspace_id", "")
    print(identifier, workspace.get("label") or identifier, first.get(identifier, ""), sep="\t")'
}

herdr_workspace_for() {  # the workspace already showing this project, if any
    local target=$1 id label path
    if [ -f "$workspace_map" ]; then
        while IFS=$'\t' read -r id path; do
            [ "$path" = "$target" ] || continue
            if herdr workspace get "$id" >/dev/null 2>&1; then printf '%s' "$id"; return; fi
        done < "$workspace_map"
    fi
    while IFS=$'\t' read -r id label path; do
        if [ "$path" = "$target" ]; then printf '%s' "$id"; return; fi
    done < <(herdr_workspaces)
}

list_choices() {
    local id name path canonical
    if [ "$backend" = herdr ]; then
        while IFS=$'\t' read -r id name path; do
            [ -n "$id" ] && printf 'session\t%s\tSession: %s\n' "$id" "$name"
        done < <(herdr_workspaces)
    else
        while IFS=$'\t' read -r id name; do
            [ -n "$id" ] && printf 'session\t%s\tSession: %s\n' "$id" "$name"
        done < <(tmux list-sessions -F $'#{session_id}\t#{session_name}' 2>/dev/null || true)
    fi
    while IFS= read -r path; do
        [ -d "$path" ] || continue
        canonical=$(cd "$path" && pwd -P)
        case "$canonical" in *$'\t'*|*$'\n'*) continue ;; esac
        printf 'project\t%s\tProject: %s\n' "$canonical" "$canonical"
    done < <(project_paths | awk '!seen[$0]++')
}

selected=$(list_choices | fzf --delimiter=$'\t' --with-nth=3.. \
    --prompt='Project > ' --header='Projects and live sessions | recent projects first | Esc: quit') || exit 0
[ -n "$selected" ] || exit 0
IFS=$'\t' read -r kind target _ <<< "$selected"
if [ "$kind" = project ]; then
    [ -d "$target" ] || exit 1
    target=$(cd "$target" && pwd -P)
    session=""
    if [ "$backend" = herdr ]; then
        session=$(herdr_workspace_for "$target")
        if [ -z "$session" ]; then
            label=$(basename "$target")
            session=$(herdr workspace create --cwd "$target" --label "$label" --no-focus | python3 -c '
import json, sys
print(json.load(sys.stdin)["result"]["workspace"]["workspace_id"], end="")') || exit 1
            [ -n "$session" ] || exit 1
            tmp=$(mktemp "$TMUX_DATA_DIR/workspaces.XXXXXX")
            { printf '%s\t%s\n' "$session" "$target"; [ ! -f "$workspace_map" ] || grep -v "^$session"$'\t' "$workspace_map"; } > "$tmp"
            mv -f "$tmp" "$workspace_map"
        fi
    else
    while IFS=$'\t' read -r id path; do
        if [ "$path" = "$target" ]; then session="$id"; break; fi
    done < <(tmux list-sessions -F $'#{session_id}\t#{@project_path}' 2>/dev/null || true)
    fi
    if [ -z "$session" ]; then
        label=$(basename "$target" | tr -c '[:alnum:]_-' '-')
        checksum=$(printf '%s' "$target" | cksum); checksum=${checksum%% *}
        name="${label:-project}-$checksum"
        candidate="$name"; suffix=1
        while tmux has-session -t "=$candidate" 2>/dev/null; do
            candidate="$name-$suffix"; suffix=$((suffix + 1))
        done
        session=$(tmux new-session -d -P -F '#{session_id}' -s "$candidate" -c "$target")
        tmux set-option -t "$session" @project_path "$target"
    fi
    tmp=$(mktemp "$TMUX_DATA_DIR/recent.XXXXXX")
    { printf '%s\n' "$target"; [ ! -f "$recent" ] || cat "$recent"; } | awk '!seen[$0]++ && count++ < 100' > "$tmp"
    mv -f "$tmp" "$recent"
    target="$session"
fi
if [ "$backend" = herdr ]; then herdr workspace focus "$target" >/dev/null
elif [ -n "${TMUX:-}" ]; then tmux switch-client -t "$target"; else tmux attach-session -t "$target"; fi
