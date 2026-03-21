#!/usr/bin/env bash
# tmux web search — fetch results via DuckDuckGo, pick with fzf, open in browser
# Usage: websearch.sh [query]           — search all sites
#        websearch.sh --pick [query]    — pick a site scope first

set -euo pipefail

PICK=false
if [[ "${1:-}" == "--pick" ]]; then
    PICK=true
    shift
fi

QUERY="${*:-}"

if [[ -z "$QUERY" ]]; then
    printf "Search: "
    read -r QUERY
    [[ -z "$QUERY" ]] && exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SITE_ARGS=""

# Cross-platform browser opener
if command -v xdg-open >/dev/null 2>&1; then
    OPENER="xdg-open"
elif command -v open >/dev/null 2>&1; then
    OPENER="open"
else
    OPENER="w3m"
fi

if $PICK; then
    ENGINE=$(printf 'All\nWikipedia\nGitHub\nStackOverflow\nMDN Web Docs\n' \
        | fzf --height=10 --prompt="Search scope: " --reverse) || exit 0
    case "$ENGINE" in
        Wikipedia)      SITE_ARGS="--site wikipedia" ;;
        GitHub)         SITE_ARGS="--site github" ;;
        StackOverflow)  SITE_ARGS="--site stackoverflow" ;;
        "MDN Web Docs") SITE_ARGS="--site mdn" ;;
        All)            ;;
    esac
fi

# Fetch results
RESULTS=$(python3 "$SCRIPT_DIR/websearch_fetch.py" "$QUERY" $SITE_ARGS 2>/dev/null)

if [[ -z "$RESULTS" ]]; then
    echo "No results found."
    read -rn1
    exit 0
fi

# Pick with fzf — Enter opens in browser, Ctrl-W opens in w3m
SELECTED=$(echo "$RESULTS" \
    | fzf --ansi --no-sort --reverse \
        --header="[$QUERY] Enter=open in browser | Ctrl-W=open in w3m | Esc=quit" \
        --expect="ctrl-w" \
    ) || exit 0

# Parse fzf --expect output: first line is the key pressed, rest is selection
KEY=$(echo "$SELECTED" | head -1)
LINE=$(echo "$SELECTED" | tail -n +2)

# Extract URL from selection or nearby lines
URL=""
if echo "$LINE" | grep -qE '^\s*https?://'; then
    URL=$(echo "$LINE" | sed 's/^ *//')
else
    # Find the result block and extract URL
    LINE_NUM=$(echo "$RESULTS" | grep -nF "$LINE" | head -1 | cut -d: -f1)
    if [[ -n "$LINE_NUM" ]]; then
        URL=$(echo "$RESULTS" | tail -n +"$LINE_NUM" | grep -m1 -oE 'https?://[^ ]+')
    fi
fi

if [[ -z "$URL" ]]; then
    exit 0
fi

if [[ "$KEY" == "ctrl-w" ]]; then
    w3m -o extbrowser="$OPENER" "$URL"
else
    $OPENER "$URL"
fi
