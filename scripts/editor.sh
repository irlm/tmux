#!/usr/bin/env bash
# Choose the editor (C-a C-v): Helix, Neovim, Vim, vi, whichever are
# installed, the current default marked. Enter opens the pick in this
# folder, in a pane beside this one, this once; C-a makes it the machine's
# default (editor= in ~/.config/tmux-user/options.env, read by C-a v,
# C-a C-f, C-a C-d and the notes on both hosts) and opens it.
#
#   editor.sh            the picker
#   editor.sh --list     the rows only, for scripts
#   editor.sh --default  the editor C-a v opens now
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
backend=$(wb_backend)

rows() {
    local current name label
    current=$(wb_editor)
    for name in hx nvim vim vi; do
        command -v "$name" >/dev/null 2>&1 || continue
        case "$name" in hx) label=Helix ;; nvim) label=Neovim ;; vim) label=Vim ;; vi) label='vi' ;; esac
        if [ "$name" = "$current" ]; then printf '%s\t● %s (%s)  default\n' "$name" "$label" "$name"
        else printf '%s\t  %s (%s)\n' "$name" "$label" "$name"; fi
    done
}

open_beside() {   # <editor>: in the pane's folder, in a split beside it
    case "$backend" in
        herdr) herdr_split_run "$(herdr_active_pane)" right "$1 ." >/dev/null || { pause_close; return 1; } ;;
        tmux) tmux split-window -h -t "${TMUX_SOURCE_PANE:-}" -c "$PWD" "$1 ." ;;
        *) exec "$1" . ;;
    esac
}

case "${1:-}" in
    --list) rows; exit 0 ;;
    --default) wb_editor; exit 0 ;;
esac
command -v fzf >/dev/null 2>&1 || { "$SCRIPT_DIR/popup.sh" fzf; exit $?; }
list=$(rows)
[ -n "$list" ] || { echo 'No editor is installed (Helix, Neovim, Vim).'; pause_close; exit 1; }
picked=$(printf '%s\n' "$list" | fzf --delimiter=$'\t' --with-nth=2.. --tabstop=1 --no-sort --expect=ctrl-a \
    --prompt='Editor > ' --header='Enter: open it here this once · C-a: make it the default and open it') || exit 0
key=${picked%%$'\n'*}; line=${picked#*$'\n'}; editor=${line%%$'\t'*}
[ -n "$editor" ] && [ "$key" != "$line" ] || exit 0
if [ "$key" = ctrl-a ]; then
    wb_set_user_option editor "$editor" || { echo 'Could not save the default.'; pause_close; exit 1; }
fi
open_beside "$editor"
