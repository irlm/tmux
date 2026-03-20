#!/usr/bin/env bash
set -euo pipefail

REPO_BASE="https://github.com/irlm"

update_repo() {
    local name="$1"
    local dir="$2"
    local repo="$REPO_BASE/$name.git"

    echo "── $name ──"

    if [ ! -d "$dir/.git" ]; then
        echo "  Not installed, skipping."
        return
    fi

    cd "$dir"

    if ! git fetch "$repo" main --quiet 2>/dev/null; then
        if ! git fetch origin main --quiet 2>/dev/null; then
            echo "  Error: cannot reach GitHub."
            return
        fi
        local remote
        remote=$(git rev-parse origin/main)
    else
        local remote
        remote=$(git rev-parse FETCH_HEAD)
    fi

    local local_rev
    local_rev=$(git rev-parse HEAD)

    if [ "$local_rev" = "$remote" ]; then
        echo "  Already up to date."
    else
        echo "  New commits:"
        git log --oneline HEAD.."$remote"
        git pull --ff-only "$repo" main
        echo "  Updated."
    fi
}

echo "=== Updating dotfiles ==="
echo ""

# Update tmux config
update_repo "tmux" "$HOME/.config/tmux"

# Install/update TPM plugins
if [ -x "$HOME/.config/tmux/plugins/tpm/bin/install_plugins" ]; then
    echo "  Installing/updating tmux plugins..."
    "$HOME/.config/tmux/plugins/tpm/bin/install_plugins" 2>/dev/null || true
fi

# Reload tmux config if running
if tmux info &>/dev/null; then
    tmux source-file "$HOME/.config/tmux/tmux.conf"
    echo "  Config reloaded."
fi

echo ""

# Update nvim config
update_repo "nvim" "$HOME/.config/nvim"

# Update nvim plugins if nvim is installed
if command -v nvim &>/dev/null; then
    echo "  Updating nvim plugins..."
    nvim --headless "+Lazy! sync" +qa 2>/dev/null || true
    echo "  Done."
fi

# Check language toolchain
echo ""
echo "── language toolchain ──"
OS="$(uname -s)"
missing=""
command -v node &>/dev/null    || missing="$missing node"
command -v go &>/dev/null      || missing="$missing go"
command -v rustc &>/dev/null   || missing="$missing rust"
command -v java &>/dev/null    || missing="$missing java"
command -v python3 &>/dev/null || missing="$missing python3"
if command -v rustup &>/dev/null; then
    rustup component list 2>/dev/null | grep -q 'rust-analyzer.*installed' || missing="$missing rust-analyzer"
fi
command -v metals &>/dev/null  || missing="$missing metals"
command -v docker &>/dev/null  || missing="$missing docker"

if [ -z "$missing" ]; then
    echo "  All toolchains present."
else
    echo "  Missing:$missing"
    echo "  Run install.sh or setup.sh to install them."
fi

echo ""
echo "=== All up to date! ==="
