#!/usr/bin/env bash
# What changed in this repository, file by file, with the diff beside it:
# the review step after an agent reports done. Enter opens the file in
# $EDITOR at its first changed line, then comes back to the list.
#
#   review.sh [dir]     the picker over the repository containing dir (C-a C-d)
#
# Keys: Enter open · C-a send this file's diff to the agent · C-w the whole
# diff · C-d toggle difftastic / delta · C-y copy the path · C-g lazygit.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

diff_tool() {   # delta when installed, difft on request, plain git otherwise
    case "${WB_DIFF_TOOL:-}" in
        difft) command -v difft >/dev/null 2>&1 && { echo difft; return; } ;;
        delta|'') command -v delta >/dev/null 2>&1 && { echo delta; return; } ;;
    esac
    echo git
}

# The diff of one file against HEAD (an untracked file shows whole).
file_diff() {
    local root=$1 file=$2 color=${3:-always}
    if git -C "$root" ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
        case "$(diff_tool)" in
            difft) DFT_COLOR="$color" DFT_WIDTH="${FZF_PREVIEW_COLUMNS:-${COLUMNS:-120}}" DFT_DISPLAY="${WB_DIFFT_DISPLAY:-inline}" \
                   git -C "$root" -c diff.external=difft diff HEAD -- "$file" ;;
            delta) git -C "$root" diff HEAD --color="$color" -- "$file" | delta --paging=never --line-numbers --width "${FZF_PREVIEW_COLUMNS:-${COLUMNS:-120}}" ;;
            *) git -C "$root" diff HEAD --color="$color" -- "$file" ;;
        esac
    elif command -v bat >/dev/null 2>&1; then
        bat --color="$color" --style=numbers,header -- "$root/$file"
    else
        printf '%s (new file)\n\n' "$file"; cat -- "$root/$file"
    fi
}

# "status\t+added\t-removed\tpath" per changed file, untracked included.
changed_files() {
    local root=$1
    git -C "$root" status --porcelain=v1 --untracked-files=all 2>/dev/null | python3 -c '
import subprocess, sys
root = sys.argv[1]
numstat = {}
for line in subprocess.run(["git", "-C", root, "diff", "HEAD", "--numstat"], capture_output=True, text=True).stdout.splitlines():
    parts = line.split("\t")
    if len(parts) == 3:
        numstat[parts[2]] = (parts[0], parts[1])
for line in sys.stdin.read().splitlines():
    if len(line) < 4:
        continue
    code, path = line[:2], line[3:]
    if " -> " in path:
        path = path.split(" -> ", 1)[1]
    if path.startswith("\"") and path.endswith("\""):
        path = path[1:-1]
    added, removed = numstat.get(path, ("", ""))
    if code == "??":
        try:
            with open(f"{root}/{path}", "rb") as stream:
                added, removed = str(sum(1 for _ in stream)), "0"
        except OSError:
            added, removed = "", ""
    label = {"??": "new", "A ": "added", "M ": "staged", " M": "edited", "MM": "edited", "D ": "deleted", " D": "deleted", "R ": "renamed", "RM": "renamed"}.get(code, code.strip() or "?")
    plus = f"+{added}" if added not in ("", "-") else ""
    minus = f"-{removed}" if removed not in ("", "-") else ""
    print("\t".join([path, f"{label:<8}", f"{plus:>6} {minus:>6}", path]))
' "$root"
}

first_changed_line() {
    local root=$1 file=$2 line
    line=$(git -C "$root" diff -U0 HEAD -- "$file" 2>/dev/null | sed -n 's/^@@ -[0-9,]* +\([0-9]*\).*/\1/p' | head -1)
    printf '%s' "${line:-1}"
}

open_in_editor() {
    local root=$1 file=$2 line editor=${EDITOR:-hx}
    line=$(first_changed_line "$root" "$file")
    case "$editor" in
        *hx*) (cd "$root" && "$editor" "$file:$line") ;;
        *vim*|*vi) (cd "$root" && "$editor" "+$line" "$file") ;;
        *) (cd "$root" && "$editor" "$file") ;;
    esac
}

send_to_agent() {
    local root=$1 file=$2 body
    body=$(file_diff "$root" "$file" never | head -300)
    printf 'About your change in %s:\n```diff\n%s\n```\n' "$file" "$body" | "$SCRIPT_DIR/agent-send.sh"
    sleep 0.8
}

case "${1:-}" in
    --preview) file_diff "$2" "$3"; exit ;;
esac
start=${1:-$PWD}
root=$(git -C "$start" rev-parse --show-toplevel 2>/dev/null) || { printf 'Not a Git repository: %s\n' "$start"; pause_close; exit 1; }
command -v fzf >/dev/null 2>&1 || { "$SCRIPT_DIR/popup.sh" fzf; exit $?; }
export WB_DIFF_TOOL="${WB_DIFF_TOOL:-}"
while :; do
    list=$(changed_files "$root")
    if [ -z "$list" ]; then printf 'Nothing changed in %s (clean against HEAD).\n' "$root"; pause_close; exit 0; fi
    count=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
    stat=$(git -C "$root" diff HEAD --shortstat 2>/dev/null | sed 's/^ *//')
    picked=$(printf '%s\n' "$list" | fzf --delimiter=$'\t' --with-nth=2.. --tabstop=1 --no-sort \
        --prompt="Review ($(diff_tool)) > " --expect=ctrl-a,ctrl-w,ctrl-d,ctrl-y,ctrl-g \
        --header="$count file(s) · ${stat:-untracked only} · Enter open · C-a send to agent · C-w whole diff · C-d delta/difft · C-y copy path · C-g lazygit" \
        --preview "WB_DIFF_TOOL=$(printf '%q' "$WB_DIFF_TOOL") bash $(printf '%q' "$0") --preview $(printf '%q' "$root") {1}" \
        --preview-window='right,65%,border-left') || exit 0
    key=""; line=$picked
    case "$picked" in *$'\n'*) key=${picked%%$'\n'*}; line=${picked#*$'\n'} ;; esac
    file=${line%%$'\t'*}
    case "$key" in
        ctrl-a) [ -n "$file" ] && send_to_agent "$root" "$file" ;;
        ctrl-w) git -C "$root" diff HEAD --color=always | { command -v delta >/dev/null 2>&1 && delta --paging=always --line-numbers || less -KR; } ;;
        ctrl-d) if [ "$WB_DIFF_TOOL" = difft ]; then WB_DIFF_TOOL='delta'; else WB_DIFF_TOOL='difft'; fi
                command -v difft >/dev/null 2>&1 || [ "$WB_DIFF_TOOL" != difft ] || { echo 'difft is not installed (difftastic).'; sleep 1; WB_DIFF_TOOL='delta'; }
                export WB_DIFF_TOOL ;;
        ctrl-y) [ -n "$file" ] && printf '%s' "$file" | "$SCRIPT_DIR/clipboard.sh" ;;
        ctrl-g) (cd "$root" && "$SCRIPT_DIR/lazygit.sh") ;;
        *) [ -n "$file" ] || exit 0
           open_in_editor "$root" "$file" ;;
    esac
done
