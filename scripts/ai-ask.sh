#!/usr/bin/env bash
# Quick AI answer — ask a question, get a response, scroll, quit
# Usage: ai-ask.sh [question]
set -euo pipefail

QUERY="${*:-}"

if [[ -z "$QUERY" ]]; then
    printf "Ask AI: "
    read -r QUERY
    [[ -z "$QUERY" ]] && exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "claude not found. Install Claude Code first."
    read -rn1
    exit 1
fi

claude -p "$QUERY" 2>/dev/null
echo
echo "[press any key to close]"
read -rn1
