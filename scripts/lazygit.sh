#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/popup.sh" --exec-need lazygit -- python3 "$SCRIPT_DIR/appearance.py" lazygit "$@"
