#!/usr/bin/env bash
# Run on Windows through Git Bash (tests/test-windows.ps1), and in the Unix
# suite against a Python with a legacy default encoding: the Python the popups
# use must read Herdr's UTF-8 JSON from a pipe and write a state icon to one.
# Windows Python does neither by default (cp1252); scripts/lib.sh turns its
# UTF-8 mode on.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh
python3 -c 'pass' 2>/dev/null || { echo 'No working Python: pipe check skipped'; exit 0; }
spinner=$'\xe2\x97\x90'   # U+25D0, the first frame of the spinner Claude Code puts in a pane title
got=$(printf '{"title":"%s Port the report"}' "$spinner" |
      python3 -c 'import json, sys; print(json.load(sys.stdin)["title"].split()[0], end="")' 2>&1)
if [ "$got" != "$spinner" ]; then
    printf 'Python did not pass UTF-8 through a pipe: %s\n' "$got" >&2
    exit 1
fi
echo 'Python pipes are UTF-8: passed'
