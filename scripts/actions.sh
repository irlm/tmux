#!/usr/bin/env bash
# One action registry drives bindings, the palette, and popup help.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
registry="$SCRIPT_DIR/../actions.tsv"
backend=$(wb_backend)
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
    local key id label tool hosts state
    while IFS=$'\t' read -r key id label tool hosts _; do
        [ "$key" != key ] || continue
        hosts=${hosts%$'\r'}   # a CRLF checkout must not hide every row
        wb_host_match "$hosts" || continue
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
        pick|urls) "$SCRIPT_DIR/pick.sh" "${id/pick/hints}" ;;
        open-file) "$SCRIPT_DIR/pick.sh" files ;;
        editor)
            # Helix (or $EDITOR) in this folder, in a pane beside this one:
            # under tmux `open` already made the split and runs this inside it.
            editor=${EDITOR:-hx}; command -v "$editor" >/dev/null 2>&1 || editor=hx
            if [ "$backend" = herdr ]; then
                herdr_split_run "$(herdr_active_pane)" right "$editor ." >/dev/null || { pause_close; return 1; }
                return
            fi
            exec "$editor" . ;;
        agents) "$SCRIPT_DIR/agents.sh" ;;
        review) "$SCRIPT_DIR/review.sh" ;;
        worktree) "$SCRIPT_DIR/worktree.sh" ;;
        llm) if python3 -c 'import curses' 2>/dev/null; then python3 "$SCRIPT_DIR/llm_usage.py"
             else python3 "$SCRIPT_DIR/llm_usage.py" --plain | less -R; fi ;;
        palette) selected=$(list_actions | fzf --delimiter=$'\t' --with-nth=2.. --prompt='Command > ') || return 0
                 [ -n "$selected" ] || return 0
                 selected=${selected%%$'\t'*}
                 case "$selected" in ssh|ssh-split|editor) "$SCRIPT_DIR/actions.sh" open "$selected" ;;
                     *) "$SCRIPT_DIR/actions.sh" run "$selected" ;; esac ;;
        help)
            # F quits less with status 70 (ASCII F), then opens the palette.
            # Keep less's stderr on the terminal so short help can display
            # without getting stuck in "Waiting for data".
            # Without lesskey support (less < 582) F would start
            # follow mode, so the hint is dropped. ':' is escaped: it is a
            # prompt directive in less. --fill gives less a full screen: a
            # shorter file is drawn at the bottom, G scrolls "~" rows in above
            # it, and only g brings the title back to the top.
            output=$(mktemp -d) || return 1
            if less --lesskey-src=/dev/null </dev/null >/dev/null 2>&1; then
                printf '#command\nF quit F\n' > "$output/lesskey"
                python3 "$SCRIPT_DIR/help.py" --fill | less --lesskey-src="$output/lesskey" -KR \
                    -P 'Help | F\: search commands | Space/b\: page | /\: search | q\: close'
                rc=$?
            else
                python3 "$SCRIPT_DIR/help.py" --no-palette --fill | less -KR -P 'Help | Space/b\: page | /\: search | q\: close'
                rc=$?
            fi
            rm -rf -- "$output"
            if [ "$rc" -eq 70 ]; then run_action palette; else return "$rc"; fi ;;
        themes) "$SCRIPT_DIR/themes.sh" ;;
        special-days) python3 "$SCRIPT_DIR/special_days.py" --pick ;;
        editor-help|nvim-help)
            if [ -f "${NVIM_CONFIG_DIR:-$HOME/.config/nvim}/init.lua" ]; then
                less -KR "$SCRIPT_DIR/../cheatsheet-helix.txt" "$SCRIPT_DIR/../cheatsheet-nvim.txt"
            else
                less -KR "$SCRIPT_DIR/../cheatsheet-helix.txt"
            fi ;;
        notes|projects) if [ "$id" = notes ]; then output=notes.sh; else output=sessionizer.sh; fi
                        if ! row_available fzf; then "$SCRIPT_DIR/popup.sh" fzf; return $?; fi
                        "$SCRIPT_DIR/$output" ;;
        history)
            if [ "$backend" = herdr ]; then
                herdr pane read "$(herdr_active_pane)" --source recent-unwrapped --lines 10000 | fzf --tac --no-sort
            else
                tmux capture-pane -pS -10000 -t "${TMUX_SOURCE_PANE:-${TMUX_PANE:-}}" | fzf --tac --no-sort
            fi ;;
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
            if [ "$backend" = herdr ]; then
                case "$id" in
                    new-session) herdr workspace create --cwd "$PWD" --label "$query" --focus >/dev/null ;;
                    rename-session) herdr workspace rename "${HERDR_WORKSPACE_ID:?}" "$query" >/dev/null ;;
                    rename-window) herdr tab rename "${HERDR_TAB_ID:?}" "$query" >/dev/null ;;
                esac
                return
            fi
            case "$id" in
                new-session) tmux new-session -d -s "$query" && tmux switch-client -t "=$query" ;;
                rename-session) tmux rename-session -- "$query" ;;
                rename-window) tmux rename-window -- "$query" ;;
            esac ;;
        update)
            # Windows (Git Bash under Herdr): the PowerShell installer is the updater.
            case "$(uname -s)" in
                MINGW*|MSYS*|CYGWIN*) powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$SCRIPT_DIR/../install.ps1")"; rc=$? ;;
                *) "$SCRIPT_DIR/../update.sh"; rc=$? ;;
            esac
            pause_close; return "$rc" ;;
        ssh|ssh-split)
            # Under Herdr a saved machine (herdr machine add) puts the server's
            # agents in the sidebar; this is the quick plain-ssh path.
            if [ "$backend" = herdr ]; then
                printf 'SSH host (alias or user@host): '; IFS= read -r query || return 0
                [ -n "$query" ] || return 0
                case "$query" in -*|*[[:space:]]*) echo 'Enter a host alias or user@host; put SSH options in ~/.ssh/config.'; pause_close; return 1 ;; esac
                if [ "$id" = ssh-split ]; then
                    herdr_split_run "$(herdr_active_pane)" right "ssh $(printf '%q' "$query")" >/dev/null || { pause_close; return 1; }
                    return
                fi
                output=$(herdr tab create --label "ssh $query" --focus 2>&1) || { printf 'Could not open a tab: %s\n' "$output"; pause_close; return 1; }
                output=$(printf '%s' "$output" | python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]; print(r["root_pane"]["pane_id"], end="")')
                herdr pane run "$output" "ssh $(printf '%q' "$query")" >/dev/null || { pause_close; return 1; }
                return
            fi
            "$SCRIPT_DIR/ssh-remote.sh" ;;
        *) printf 'Unknown action: %s\n' "$id" >&2; return 2 ;;
    esac
}
case "${1:-palette}" in
    bind)
        while IFS=$'\t' read -r key id _ _ hosts _; do
            hosts=${hosts%$'\r'}
            [ "$key" != key ] && [ "${hosts:-all}" != herdr ] || continue
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
        if [ "$backend" = herdr ]; then "$SCRIPT_DIR/actions.sh" run "$id"; exit $?; fi
        # Pass cwd as a tmux argument; free text is read inside the popup.
        cwd=$(tmux display-message -p '#{pane_current_path}')
        pane=$(tmux display-message -p '#{pane_id}')
        printf -v command 'TMUX_SOURCE_PANE=%q %q run %q' "$pane" "$SCRIPT_DIR/actions.sh" "$id"
        case "$id" in
            ssh) tmux new-window -n ssh -c "$cwd" "$command" ;;
            ssh-split|editor) tmux split-window -h -c "$cwd" "$command" ;;
            *) size=$(tmux_option @popup_size 85%)
               case "$size" in *[!0-9%]*|'') size=85% ;; esac
               width=$size; height=$size
               # A row's own size (WIDTHxHEIGHT, cells or percent) fits a popup to its content.
               own=$(awk -F '\t' -v id="$id" '$2 == id {print $6}' "$registry")
               case "$own" in
                   [0-9]*x[0-9]*) width=${own%x*}; height=${own#*x} ;;
               esac
               tmux display-popup -d "$cwd" -w "$width" -h "$height" -E "$command" ;;
        esac ;;
    *) run_action "$1" ;;
esac
