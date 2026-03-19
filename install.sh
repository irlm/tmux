#!/usr/bin/env bash
set -euo pipefail

echo "=== dotfiles installer ==="
echo ""

# Detect OS
OS="$(uname -s)"
echo "OS: $OS"

# ─── Install dependencies ────────────────────────────────
echo ""
echo "Installing dependencies..."

if [ "$OS" = "Darwin" ]; then
    if ! command -v brew &>/dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install tmux neovim lazygit fzf zoxide bat gh fastfetch btop oh-my-posh
elif [ "$OS" = "Linux" ]; then
    sudo apt-get update
    sudo apt-get install -y tmux fzf bat snapd
    # neovim via snap (apt version is too old for LazyVim, needs 0.10+)
    install_nvim_snap=false
    if ! command -v nvim &>/dev/null; then
        install_nvim_snap=true
    else
        nvim_ver=$(nvim --version | head -1 | grep -oP '\d+\.\d+' | head -1)
        nvim_major=$(echo "$nvim_ver" | cut -d. -f1)
        nvim_minor=$(echo "$nvim_ver" | cut -d. -f2)
        if [ "$nvim_major" -eq 0 ] && [ "$nvim_minor" -lt 10 ]; then
            echo "Found neovim $nvim_ver (too old, need 0.10+). Upgrading..."
            # Remove old apt version if present
            sudo apt-get remove -y neovim neovim-runtime 2>/dev/null || true
            install_nvim_snap=true
        fi
    fi
    if $install_nvim_snap; then
        echo "Installing neovim via snap (latest stable)..."
        sudo snap install nvim --classic
    fi
    # lazygit
    if ! command -v lazygit &>/dev/null; then
        LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
        curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
        sudo tar xf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit
    fi
    # zoxide
    command -v zoxide &>/dev/null || curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    # oh-my-posh
    command -v oh-my-posh &>/dev/null || curl -s https://ohmyposh.dev/install.sh | bash -s
fi

# ─── Clone configs ────────────────────────────────────────
echo ""
echo "Setting up configs..."

REPO_BASE="https://github.com/irlm"

# tmux
if [ ! -d "$HOME/.config/tmux/.git" ]; then
    echo "Cloning tmux config..."
    rm -rf "$HOME/.config/tmux"
    git clone "$REPO_BASE/tmux.git" "$HOME/.config/tmux"
else
    echo "tmux config already exists, pulling..."
    cd "$HOME/.config/tmux" && git pull --ff-only
fi

# neovim
if [ ! -d "$HOME/.config/nvim/.git" ]; then
    echo "Cloning nvim config..."
    rm -rf "$HOME/.config/nvim"
    git clone "$REPO_BASE/nvim.git" "$HOME/.config/nvim"
else
    echo "nvim config already exists, pulling..."
    cd "$HOME/.config/nvim" && git pull --ff-only
fi

# ─── TPM plugins ──────────────────────────────────────────
echo ""
echo "Installing tmux plugins..."
if [ ! -d "$HOME/.config/tmux/plugins/tpm" ]; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
fi
"$HOME/.config/tmux/plugins/tpm/bin/install_plugins" || true

# ─── Shell config ─────────────────────────────────────────
echo ""
if ! grep -q "oh-my-posh" "$HOME/.zshrc" 2>/dev/null; then
    echo "Adding oh-my-posh to .zshrc..."
    cat >> "$HOME/.zshrc" << 'ZSHRC'

# ─── oh-my-posh prompt ─────────────────────────────────
eval "$(oh-my-posh init zsh --config ~/.config/tmux/nord.omp.json)"
ZSHRC
fi

if ! grep -q "zoxide" "$HOME/.zshrc" 2>/dev/null; then
    echo "Adding zoxide to .zshrc..."
    echo 'command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"' >> "$HOME/.zshrc"
fi

# ─── Create data dirs ─────────────────────────────────────
mkdir -p "$HOME/.local/share/tmux"

# ─── Done ─────────────────────────────────────────────────
echo ""
echo "=== Install complete! ==="
echo ""
echo "Next steps:"
echo "  1. Open a new terminal"
echo "  2. Run: tmux"
echo "  3. Press C-a I to install tmux plugins"
echo "  4. Run: nvim (plugins auto-install on first launch)"
echo ""
