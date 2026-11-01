#!/usr/bin/env bash
# One action registry drives bindings, the palette, and popup help.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
registry="$SCRIPT_DIR/../actions.tsv"
row_available() {
    local tools=$1 candidate group found
    [ "$tools" != - ] || return 0
    [ "$tools" != @ai ] || tools="${TMUX_AI_COMMAND:-$(tmux_option @ai_command claude)}"
    local -a groups candidates
    IFS='&' read -r -a groups <<< "$tools"
    for group in "${groups[@]}"; do
        found=0
        IFS='|' read -r -a candidates <<< "$group"
        for candidate in "${candidates[@]}"; do
            if command -v "$candidate" >/dev/null 2>&1; then found=1; break; fi
        done
        [ "$found" -eq 1 ] || return 1
    done
}
list_actions() {
    local key id label tool state
    while IFS=$'\t' read -r key id label tool; do
        [ "$key" != key ] || continue
        state=ready; row_available "$tool" || state="missing $tool"
        printf '%s\tC-a %-4s %-32s [%s]\n' "$id" "$key" "$label" "$state"
    done < "$registry"
}
run_action() {
    local id=$1 query output rc
    case "$id" in
        git) "$SCRIPT_DIR/lazygit.sh" ;;
        github) "$SCRIPT_DIR/popup.sh" --gh-ext gh-dash -- 'gh dash' ;;
        docker) "$SCRIPT_DIR/popup.sh" lazydocker ;;
        top) "$SCRIPT_DIR/popup.sh" --any btop htop ;;
        shell) "${SHELL:-/bin/sh}" ;;
        info) if command -v fastfetch >/dev/null 2>&1; then fastfetch --pipe false | less -R;
              else { uname -a; uptime; df -h /; } | less -R; fi ;;
        palette) selected=$(list_actions | fzf --delimiter=$'\t' --with-nth=2.. --prompt='Command > ') || return 0
                 [ -n "$selected" ] || return 0
                 selected=${selected%%$'\t'*}
                 case "$selected" in ssh|ssh-split) "$SCRIPT_DIR/actions.sh" open "$selected" ;;
                     *) "$SCRIPT_DIR/actions.sh" run "$selected" ;; esac ;;
        help) python3 "$SCRIPT_DIR/help.py" | less -KR -P 'Help | Space/b: page | /: search | q: close' ;;
        themes) "$SCRIPT_DIR/themes.sh" ;;
        nvim-help) less -KR "$SCRIPT_DIR/../cheatsheet-nvim.txt" ;;
        notes|projects) if [ "$id" = notes ]; then output=notes.sh; else output=sessionizer.sh; fi
                        if ! row_available fzf; then "$SCRIPT_DIR/popup.sh" fzf; return $?; fi
                        "$SCRIPT_DIR/$output" ;;
        history) tmux capture-pane -pS -10000 -t "${TMUX_SOURCE_PANE:-${TMUX_PANE:-}}" | fzf --tac --no-sort ;;
        search) "$SCRIPT_DIR/websearch.sh" ;;
        scoped-search) "$SCRIPT_DIR/websearch.sh" --pick ;;
        ai) "$SCRIPT_DIR/ai-ask.sh" ;;
        man|cheat|tldr)
            printf '%s: ' "$id"; IFS= read -r query || return 0
            [ -n "$query" ] || return 0
            case "$id" in
                man) "$SCRIPT_DIR/popup.sh" man -- "$query" ;;
                tldr) "$SCRIPT_DIR/popup.sh" tldr -- "$query" | less -R ;;
                cheat) output=$(mktemp)
                       query=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$query")
                       curl -fsSL --globoff "https://cheat.sh/$query" > "$output"
                       rc=$?; if [ "$rc" -eq 0 ]; then less -R "$output"; else pause_close; fi
                       rm -f -- "$output"; return "$rc" ;;
            esac ;;
        new-session|rename-session|rename-window)
            printf '%s: ' "$id"; IFS= read -r query || return 0
            [ -n "$query" ] || return 0
            case "$id" in
                new-session) tmux new-session -d -s "$query" && tmux switch-client -t "=$query" ;;
                rename-session) tmux rename-session -- "$query" ;;
                rename-window) tmux rename-window -- "$query" ;;
            esac ;;
        update) "$SCRIPT_DIR/../update.sh"; rc=$?; pause_close; return "$rc" ;;
        ssh|ssh-split) "$SCRIPT_DIR/ssh-remote.sh" ;;
        *) printf 'Unknown action: %s\n' "$id" >&2; return 2 ;;
    esac
}
case "${1:-palette}" in
    bind)
        while IFS=$'\t' read -r key id _ _; do
            [ "$key" != key ] || continue
            printf -v command '%q open %q' "$SCRIPT_DIR/actions.sh" "$id"
            tmux bind-key "$key" run-shell "$command"
        done < "$registry" ;;
    list) list_actions ;;
    run)
        id=${2:-palette}
        tools=$(awk -F '\t' -v id="$id" '$2 == id {print $4}' "$registry")
        [ -n "$tools" ] || { printf 'Unknown action: %s\n' "$id" >&2; exit 2; }
        if ! row_available "$tools"; then
            printf 'Missing dependency for %s: %s\nRepair managed tools with ~/.config/tmux/update.sh --fix; configure optional AI wrappers with @ai_command.\n' "$id" "$tools"
            pause_close
            exit 127
        fi
        run_action "$id" ;;

    open)
        id=${2:-palette}
        # Pass cwd as a tmux argument; free text is read inside the popup.
        cwd=$(tmux display-message -p '#{pane_current_path}')
        pane=$(tmux display-message -p '#{pane_id}')
        printf -v command 'TMUX_SOURCE_PANE=%q %q run %q' "$pane" "$SCRIPT_DIR/actions.sh" "$id"
        case "$id" in
            ssh) tmux new-window -n ssh -c "$cwd" "$command" ;;
            ssh-split) tmux split-window -h -c "$cwd" "$command" ;;
            *) size=$(tmux_option @popup_size 85%)
               case "$size" in *[!0-9%]*|'') size=85% ;; esac
               tmux display-popup -d "$cwd" -w "$size" -h "$size" -E "$command" ;;
        esac ;;
    *) run_action "$1" ;;
esac
