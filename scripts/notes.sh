#!/usr/bin/env bash
# Quick notes. Keep filenames separate from display text.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
NOTES_DIR="${TMUX_NOTES_DIR:-$TMUX_DATA_DIR/notes}"
if [ "${1:-}" = --preview ]; then
    name=${2:-}
    case "$name" in */*|*..*) exit 0 ;; esac
    if [ -f "$NOTES_DIR/$name" ]; then cat -- "$NOTES_DIR/$name"; else printf 'Create a new note'; fi
    exit 0
fi
mkdir -p "$NOTES_DIR"
printf -v preview_command '%q --preview {1}' "$SCRIPT_DIR/notes.sh"

list_notes() {
    printf 'new\t+ New note\n'
    local file name preview
    for file in "$NOTES_DIR"/*.md; do
        [ -f "$file" ] || continue
        name=${file##*/}
        case "$name" in *$'\t'*|*$'\n'*) continue ;; esac
        IFS= read -r preview < "$file" || true
        preview=${preview//$'\t'/ }
        printf '%s\t%s  |  %s\n' "$name" "${name%.md}" "$preview"
    done
}

while true; do
    selected=$(list_notes | fzf --delimiter=$'\t' --with-nth=2.. \
        --prompt='Notes > ' --header='Enter: edit | Ctrl-d: delete | Esc: quit' \
        --expect=ctrl-d --preview="$preview_command" --preview-window=right:50%:wrap) || exit 0
    [ -n "$selected" ] || exit 0
    key=${selected%%$'\n'*}
    choice=${selected#*$'\n'}
    name=${choice%%$'\t'*}
    [ -n "$name" ] || exit 0
    if [ "$key" = ctrl-d ]; then
        [ "$name" != new ] || continue
        file="$NOTES_DIR/$name"
        printf "Delete '%s'? [y/N] " "${name%.md}"
        IFS= read -r answer || exit 0
        case "$answer" in y|Y) rm -- "$file" ;; esac
        continue
    fi
    if [ "$name" = new ]; then
        printf 'Note name (Enter for date, Esc then Enter to cancel): '
        IFS= read -r name || exit 0
        case "$name" in *$'\033'*) exit 0 ;; esac
        [ -n "$name" ] || name=$(date +'%Y-%m-%d_%H%M%S')
        name=$(printf '%s' "$name" | tr ' /' '-_' | tr -cd '[:alnum:]_-')
        if [ -z "$name" ]; then printf 'Enter a name with letters or numbers.\n'; continue; fi
        file="$NOTES_DIR/$name.md"
        if [ ! -e "$file" ]; then
            (set -C; printf '# %s\n\n' "$name" > "$file") 2>/dev/null || {
                [ -f "$file" ] || exit 1
            }
        fi
    else
        file="$NOTES_DIR/$name"
    fi
    "${EDITOR:-vim}" "$file"
    exit 0
done
