#!/usr/bin/env bash
set -euo pipefail

TMUX_DIR="$HOME/.config/tmux"
REPO_HTTPS="https://github.com/irlm/tmux.git"

cd "$TMUX_DIR"

echo "Checking for updates..."

# Use HTTPS for fetch (works without SSH keys)
if ! git fetch "$REPO_HTTPS" main --quiet 2>/dev/null; then
    # Fallback to configured remote
    if ! git fetch origin main --quiet 2>/dev/null; then
        echo "Error: cannot reach GitHub. Check your internet connection."
        exit 1
    fi
    REMOTE=$(git rev-parse origin/main)
else
    REMOTE=$(git rev-parse FETCH_HEAD)
fi

LOCAL=$(git rev-parse HEAD)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "Already up to date."
    exit 0
fi

# Show what's new
echo ""
echo "New commits available:"
git log --oneline HEAD.."$REMOTE"
echo ""

# Pull the new version via HTTPS
echo "Updating..."
git pull --ff-only "$REPO_HTTPS" main

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
