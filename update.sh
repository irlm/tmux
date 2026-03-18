#!/usr/bin/env bash
set -euo pipefail

TMUX_DIR="$HOME/.config/tmux"
REPO="https://github.com/irlm/tmux.git"

cd "$TMUX_DIR"

echo "Checking for updates..."

# Fetch latest from remote
git fetch origin main --quiet

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "Already up to date."
    exit 0
fi

# Show what's new
echo ""
echo "New commits available:"
git log --oneline HEAD..origin/main
echo ""

# Pull the new version
echo "Updating..."
git pull --ff-only origin main

# Install/update TPM plugins
if [ -x "$TMUX_DIR/plugins/tpm/bin/install_plugins" ]; then
    echo "Installing/updating plugins..."
    "$TMUX_DIR/plugins/tpm/bin/install_plugins"
fi

# Reload tmux config if tmux is running
if tmux info &>/dev/null; then
    tmux source-file "$TMUX_DIR/tmux.conf"
    echo "Config reloaded."
fi

echo ""
echo "Update complete! ($(git log --oneline -1))"
