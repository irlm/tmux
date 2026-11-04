#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
site_args=()
if [ "${1:-}" = --pick ]; then
    shift
    scope=$(printf 'All\nWikipedia\nGitHub\nStackOverflow\nMDN Web Docs\n' |
        fzf --height=10 --prompt='Search scope: ' --reverse) || exit 0
    case "$scope" in
        Wikipedia) site_args=(--site wikipedia) ;;
        GitHub) site_args=(--site github) ;;
        StackOverflow) site_args=(--site stackoverflow) ;;
        'MDN Web Docs') site_args=(--site mdn) ;;
    esac
fi
query="$*"
if [ -z "$query" ]; then printf 'Search: '; IFS= read -r query || exit 0; fi
[ -n "$query" ] || exit 0
results=$(python3 "$SCRIPT_DIR/websearch_fetch.py" "$query" ${site_args[@]+"${site_args[@]}"}) || { pause_close; exit 1; }
selected=$(printf '%s\n' "$results" | fzf --delimiter=$'\t' --with-nth=2.. --no-sort --reverse \
    --header='Enter: browser | Ctrl-w: terminal browser | Esc: quit' --expect=ctrl-w) || exit 0
key=${selected%%$'\n'*}; record=${selected#*$'\n'}; url=${record%%$'\t'*}
case "$url" in http://*|https://*) ;; *) exit 1 ;; esac
if [ "$key" = ctrl-w ]; then
    "$SCRIPT_DIR/popup.sh" w3m "$url"
elif [ -n "${SSH_CONNECTION:-}" ] && [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    "$SCRIPT_DIR/popup.sh" w3m "$url"
elif command -v wslview >/dev/null 2>&1; then wslview "$url"
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url"
elif command -v open >/dev/null 2>&1; then open "$url"
elif command -v explorer.exe >/dev/null 2>&1; then explorer.exe "$url"   # Windows (Git Bash, WSL)
else "$SCRIPT_DIR/popup.sh" w3m "$url"
fi
