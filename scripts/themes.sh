#!/usr/bin/env bash
# Pick an existing palette with a preview of normal, selected and diff text.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ $# -gt 0 ]; then exec python3 "$SCRIPT_DIR/appearance.py" "$@"; fi
printf -v preview 'python3 %q preview {1}' "$SCRIPT_DIR/appearance.py"
selection=$(python3 "$SCRIPT_DIR/appearance.py" list | fzf --delimiter=$'\t' --with-nth=2.. \
    --prompt='Theme > ' --header='Enter: apply and save | Esc: cancel' \
    --preview="$preview" --preview-window=right:55%:wrap) || exit 0
[ -n "$selection" ] || exit 0
python3 "$SCRIPT_DIR/appearance.py" apply "${selection%%$'\t'*}"
