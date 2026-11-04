#!/usr/bin/env bash
# Pick text from the pane behind the popup and copy it, or pick a URL and
# open it. The Herdr stand-in for tmux-thumbs (C-a Space) and fzf-url (C-a u);
# it also runs under tmux, where it reads the pane with capture-pane.
#
#   pick.sh hints    paths, URLs, hashes, UUIDs, addresses and long tokens -> clipboard
#   pick.sh urls     URLs -> browser
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
mode=${1:-hints}

pane_text() {
    case "$(wb_backend)" in
        herdr) herdr pane read "$(herdr_active_pane)" --source recent-unwrapped --lines 2000 ;;
        *) tmux capture-pane -pJS -2000 -t "${TMUX_SOURCE_PANE:-${TMUX_PANE:-}}" ;;
    esac
}

copy() {
    if command -v pbcopy >/dev/null 2>&1; then pbcopy
    elif command -v wl-copy >/dev/null 2>&1; then wl-copy
    elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard
    elif command -v xsel >/dev/null 2>&1; then xsel --clipboard --input
    elif command -v clip.exe >/dev/null 2>&1; then clip.exe                 # Windows (Git Bash, WSL)
    else
        # OSC 52: the terminal keeps the clipboard when no tool is installed.
        printf '\033]52;c;%s\a' "$(base64 | tr -d '\n')"
    fi
}

# The extractor is kept in a variable so python reads the pane text from
# stdin rather than its own source.
read -r -d '' CANDIDATES_PY <<'PY' || true
import re, sys
mode = sys.argv[1]
text = sys.stdin.read()
url = r'(?:https?|ftp|ssh|git)://[^\s<>"\')\]]+'
patterns = [url] if mode == 'urls' else [
    url,
    r'(?:~|\.\.?)?/(?:[\w.@+-]+/)*[\w.@+-]+',          # paths
    r'[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}',  # uuids
    r'(?<![\w/])[0-9a-f]{7,40}(?![\w/])',               # git hashes
    r'(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?',                # addresses
    r'(?<![\w/.-])\d+(?:\.\d+)+(?![\w/])',             # versions
    r'(?<![\w/])[\w.-]*[-_][\w.-]*(?![\w/])',           # identifiers with - or _
]
# Earlier patterns win: a path inside a URL or a hash inside a UUID is not
# offered again on its own.
taken = []
seen = []
for pattern in patterns:
    for match in re.finditer(pattern, text):
        start, end = match.span()
        if any(start < b and end > a for a, b in taken):
            continue
        token = match.group(0).rstrip('.,;:')
        if len(token) >= 4:
            taken.append((start, end))
            if token not in seen:
                seen.append(token)
sys.stdout.write('\n'.join(seen) + ('\n' if seen else ''))
PY

candidates() { python3 -c "$CANDIDATES_PY" "$mode"; }

open_url() {
    if command -v open >/dev/null 2>&1; then open "$1"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1"
    elif command -v explorer.exe >/dev/null 2>&1; then explorer.exe "$1"   # Windows
    else printf '%s\n' "$1"; fi
}

command -v fzf >/dev/null 2>&1 || { "$SCRIPT_DIR/popup.sh" fzf; exit $?; }
list=$(pane_text | candidates)
[ -n "$list" ] || { echo 'Nothing to pick on this pane.'; pause_close; exit 0; }
case "$mode" in
    urls)
        chosen=$(printf '%s\n' "$list" | fzf --tac --no-sort --prompt='URL > ' --header='Enter: open in browser | Esc: quit') || exit 0
        [ -n "$chosen" ] || exit 0
        open_url "$chosen" ;;
    *)
        chosen=$(printf '%s\n' "$list" | fzf --tac --no-sort --multi --prompt='Copy > ' --header='Tab: select several | Enter: copy | Esc: quit') || exit 0
        [ -n "$chosen" ] || exit 0
        printf '%s' "$chosen" | tr '\n' ' ' | sed 's/ $//' | copy ;;
esac
