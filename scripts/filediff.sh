#!/usr/bin/env bash
# Helix `-d`: the diff of the file being edited, in a split beside it. Two
# steps, because the file name has to be taken before the split opens a
# scratch buffer that has none:
#   filediff.sh stage <file>   write the file's diff against HEAD to a stage file
#   filediff.sh show           print the staged diff (for :insert-output)
# An untracked file shows whole, as added lines.
set -uo pipefail
STAGE="${TMPDIR:-/tmp}/wb-filediff-$(id -u 2>/dev/null || echo "$USER")"
case "${1:-}" in
    stage)
        file=${2:-}
        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            printf 'Not a Git repository: %s\n' "$PWD" > "$STAGE"
        elif [ -z "$file" ] || [ "$file" = '[scratch]' ]; then
            printf 'No file in this buffer.\n' > "$STAGE"
        elif git ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
            git diff HEAD --no-color -- "$file" > "$STAGE"
        else
            git diff --no-index --no-color -- /dev/null "$file" > "$STAGE"
        fi
        [ -s "$STAGE" ] || printf '%s: no changes against HEAD\n' "$file" > "$STAGE"
        ;;
    show) cat "$STAGE" 2>/dev/null ;;
    *) echo 'filediff.sh stage <file> | show' >&2; exit 2 ;;
esac
