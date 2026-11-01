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

list_choices() {
    local id name path canonical
    while IFS=$'\t' read -r id name; do
        [ -n "$id" ] && printf 'session\t%s\tSession: %s\n' "$id" "$name"
    done < <(tmux list-sessions -F $'#{session_id}\t#{session_name}' 2>/dev/null || true)
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
    while IFS=$'\t' read -r id path; do
        if [ "$path" = "$target" ]; then session="$id"; break; fi
    done < <(tmux list-sessions -F $'#{session_id}\t#{@project_path}' 2>/dev/null || true)
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
if [ -n "${TMUX:-}" ]; then tmux switch-client -t "$target"; else tmux attach-session -t "$target"; fi
