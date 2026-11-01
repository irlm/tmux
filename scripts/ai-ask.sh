#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
QUERY="$*"
if [ -z "$QUERY" ]; then
    printf 'Ask AI: '
    IFS= read -r QUERY || exit 0
    [ -n "$QUERY" ] || exit 0
fi
provider="${TMUX_AI_COMMAND:-$(tmux_option @ai_command claude)}"
if ! command -v "$provider" >/dev/null 2>&1; then
    printf '%s is not installed. Set @ai_command to an installed CLI wrapper.\n' "$provider"
    pause_close
    exit 127
fi
output=$(mktemp)
trap 'rm -f "$output"' EXIT
if [ "$provider" = claude ]; then
    "$provider" -p "$QUERY" > "$output" 2>&1
else
    "$provider" "$QUERY" > "$output" 2>&1
fi
rc=$?
if [ "$rc" -ne 0 ]; then
    printf 'AI request failed (exit %s).\n\n' "$rc"
    cat "$output"
    pause_close
else
    less -R -- "$output"
fi
exit "$rc"
