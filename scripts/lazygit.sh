#!/usr/bin/env bash
# C-a g: lazygit with the chosen theme (and delta when installed). The popup
# stays open when lazygit or its launcher fails, so the reason can be read
# instead of the popup closing the instant it opens.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
"$SCRIPT_DIR/popup.sh" --exec-need lazygit -- python3 "$SCRIPT_DIR/appearance.py" lazygit "$@"
rc=$?
case "$rc" in
    0|127|130) exit "$rc" ;;   # 127: popup.sh already explained and waited
    *) printf '\nlazygit exited with status %s (directory: %s).\n' "$rc" "$PWD"; pause_close; exit "$rc" ;;
esac
