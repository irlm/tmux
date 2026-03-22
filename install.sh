#!/usr/bin/env bash
# ─── Dotfiles Installer (macOS / Linux) ──────────────────
# Quick install:  curl -sL .../install.sh | bash
# Full setup:     bash install.sh --full
# Server (light): bash install.sh --server
#
# --full:   multi-distro, shell config, nerd font, zsh plugins, dev toolchain, Docker
# --server: minimal — tmux, neovim (no LSPs), fzf, bat, btop, ripgrep
set -euo pipefail

MODE="default"
for arg in "$@"; do
    case "$arg" in
        --full|-f)   MODE="full" ;;
        --server|-s) MODE="server" ;;
    esac
done

# ─── Helper: bootstrap curl ──────────────────────────────
ensure_curl() {
    if command -v curl &>/dev/null; then return; fi
    if command -v wget &>/dev/null; then return; fi
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq curl
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y -q curl
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm curl
    elif command -v zypper &>/dev/null; then
        sudo zypper install -y curl
    fi
}

# ─── Helper: download ────────────────────────────────────
download() {
    local url="$1" dest="$2"
    if command -v curl &>/dev/null; then
        curl -sL "$url" -o "$dest"
    else
        wget -qO "$dest" "$url"
    fi
}

# ─── Full setup mode ─────────────────────────────────────
if [ "$MODE" = "full" ]; then
    echo "=== Full setup mode ==="
    echo ""
    ensure_curl
    TMPSCRIPT=$(mktemp)
    trap 'rm -f "$TMPSCRIPT"' EXIT
    download "https://raw.githubusercontent.com/irlm/tmux/main/setup.sh" "$TMPSCRIPT"
    bash "$TMPSCRIPT"
    exit 0
fi

# ─── Server (light) mode ─────────────────────────────────
if [ "$MODE" = "server" ]; then
    echo "=== Server (light) install ==="
    echo ""
    OS="$(uname -s)"

    # Ensure basics
    if [ "$OS" = "Linux" ]; then
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq curl git tmux fzf ripgrep bat htop jq build-essential w3m
            sudo apt-get install -y -qq btop 2>/dev/null || true  # not in Ubuntu < 23.10
            # neovim (apt version is too old for LazyVim on Ubuntu < 24.04)
            if ! command -v nvim &>/dev/null || [ "$(nvim --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f2)" -lt 10 ] 2>/dev/null; then
                echo "  Installing neovim via appimage..."
                sudo apt-get remove -y neovim neovim-runtime 2>/dev/null || true
                curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$(uname -m).appimage" -o /tmp/nvim.appimage
                chmod +x /tmp/nvim.appimage
                sudo mv /tmp/nvim.appimage /usr/local/bin/nvim
            fi
            # Symlink renamed binaries on Debian/Ubuntu
            [ -x /usr/bin/batcat ] && [ ! -e "$HOME/.local/bin/bat" ] && mkdir -p "$HOME/.local/bin" && ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y -q curl git tmux fzf ripgrep bat btop jq neovim gcc make w3m
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm --needed curl git tmux fzf ripgrep bat btop jq neovim base-devel w3m
        elif command -v zypper &>/dev/null; then
            sudo zypper install -y curl git tmux fzf ripgrep bat btop jq neovim gcc make w3m
        fi
    elif [ "$OS" = "Darwin" ]; then
        if ! command -v brew &>/dev/null; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
        fi
        brew install tmux neovim fzf ripgrep bat btop fastfetch jq w3m 2>/dev/null
    fi

    # fastfetch (try repo first, then GitHub release .deb/.rpm)
    if ! command -v fastfetch &>/dev/null; then
        if [ "$OS" = "Linux" ]; then
            if command -v apt-get &>/dev/null; then
                sudo apt-get install -y -qq fastfetch 2>/dev/null || {
                    # Not in repo (Ubuntu < 24.04) — install from GitHub .deb
                    echo "  fastfetch not in repo, installing from GitHub..."
                    ARCH=$(uname -m)
                    [ "$ARCH" = "x86_64" ] && ARCH="amd64"
                    [ "$ARCH" = "aarch64" ] && ARCH="aarch64"
                    FF_URL=$(curl -fsSL "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest" \
                        | grep "browser_download_url" \
                        | grep -i "linux-${ARCH}.*\\.deb" \
                        | grep -v "source" | head -1 | cut -d '"' -f 4) || true
                    if [ -n "$FF_URL" ]; then
                        curl -fsSL "$FF_URL" -o /tmp/fastfetch.deb
                        sudo dpkg -i /tmp/fastfetch.deb 2>/dev/null
                        sudo apt-get install -f -y -qq 2>/dev/null
                        rm -f /tmp/fastfetch.deb
                    fi
                }
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y -q fastfetch 2>/dev/null || true
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm --needed fastfetch 2>/dev/null || true
            fi
        fi
    fi

    # zoxide (light, useful on servers too)
    if ! command -v zoxide &>/dev/null; then
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    fi

    # tlrc (Rust tldr client — install from GitHub release, fresher than brew/repos)
    if ! command -v tldr &>/dev/null && ! command -v tlrc &>/dev/null; then
        echo "Installing tlrc from GitHub..."
        ARCH=$(uname -m)
        if [ "$OS" = "Darwin" ]; then
            TLRC_PATTERN="${ARCH}.*apple.*darwin.*\\.tar\\.gz"
        else
            TLRC_PATTERN="${ARCH}.*linux.*musl.*\\.tar\\.gz"
        fi
        TLRC_URL=$(curl -fsSL "https://api.github.com/repos/tldr-pages/tlrc/releases/latest" \
            | grep "browser_download_url" \
            | grep -i "$TLRC_PATTERN" \
            | head -1 | cut -d '"' -f 4) || true
        if [ -n "$TLRC_URL" ]; then
            TLRC_TMP=$(mktemp -d)
            curl -fsSL "$TLRC_URL" | tar xz -C "$TLRC_TMP"
            if [ -f "$TLRC_TMP/tldr" ]; then
                chmod +x "$TLRC_TMP/tldr"
                mkdir -p "$HOME/.local/bin"
                mv "$TLRC_TMP/tldr" "$HOME/.local/bin/tldr"
            fi
            rm -rf "$TLRC_TMP"
        fi
    fi

    # Clone configs
    REPO_BASE="https://github.com/irlm"
    for pair in "tmux.git:$HOME/.config/tmux" "nvim.git:$HOME/.config/nvim"; do
        repo="${pair%%:*}"
        dest="${pair##*:}"
        if [ -d "$dest/.git" ]; then
            remote=$(cd "$dest" && git remote get-url origin 2>/dev/null || echo "")
            if echo "$remote" | grep -q "irlm"; then
                echo "Updating $repo..."
                (cd "$dest" && git pull --ff-only) || true
            fi
        else
            echo "Cloning $repo..."
            mkdir -p "$(dirname "$dest")"
            rm -rf "$dest"
            git clone "$REPO_BASE/$repo" "$dest"
        fi
    done

    # TPM
    TPM_DIR="$HOME/.config/tmux/plugins/tpm"
    if [ ! -d "$TPM_DIR" ]; then
        git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
    fi
    "$TPM_DIR/bin/install_plugins" 2>/dev/null || true
    "$TPM_DIR/bin/update_plugins" all 2>/dev/null || true
    "$TPM_DIR/bin/clean_plugins" 2>/dev/null || true

    # Shell: add lightweight prompt + zoxide
    RCFILE="$HOME/.bashrc"
    [ "$OS" = "Darwin" ] && RCFILE="$HOME/.zshrc"
    if [ -f "$RCFILE" ]; then
        # Lightweight prompt (pure shell, no external binaries)
        if ! grep -q "prompt.sh\|prompt.zsh" "$RCFILE" 2>/dev/null; then
            echo '' >> "$RCFILE"
            echo '# ─── lightweight prompt (git branch, exit code, no oh-my-posh) ─' >> "$RCFILE"
            if [ "$OS" = "Darwin" ]; then
                echo '[ -f ~/.config/tmux/scripts/prompt.zsh ] && . ~/.config/tmux/scripts/prompt.zsh' >> "$RCFILE"
            else
                echo '[ -f ~/.config/tmux/scripts/prompt.sh ] && . ~/.config/tmux/scripts/prompt.sh' >> "$RCFILE"
            fi
        fi
        # zoxide
        if ! grep -q "zoxide" "$RCFILE" 2>/dev/null; then
            echo '' >> "$RCFILE"
            echo '# zoxide' >> "$RCFILE"
            if [ "$OS" = "Darwin" ]; then
                echo 'command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"' >> "$RCFILE"
            else
                echo 'command -v zoxide &>/dev/null && eval "$(zoxide init bash)"' >> "$RCFILE"
            fi
        fi
        # sudo nvim: preserve user config + editor default
        if ! grep -q "sudoedit\|EDITOR" "$RCFILE" 2>/dev/null; then
            echo '' >> "$RCFILE"
            echo '# ─── editor ─────────────────────────────────────────────' >> "$RCFILE"
            echo 'export EDITOR=nvim' >> "$RCFILE"
            echo 'export VISUAL=nvim' >> "$RCFILE"
            echo 'alias svim="sudo -E nvim"  # sudo nvim with your config' >> "$RCFILE"
        fi
    fi

    # Mark nvim as server mode (disables LSPs, heavy treesitter, Mason packages)
    touch "$HOME/.config/nvim/.server"

    # Data dirs
    mkdir -p "$HOME/.local/share/tmux" "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    echo ""
    echo "=== Server install complete! ==="
    echo ""
    echo "Installed: tmux, neovim, fzf, ripgrep, bat, btop, fastfetch, jq, zoxide"
    echo ""
    echo "Next steps:"
    echo "  1. Start tmux: tmux"
    echo "  2. Install tmux plugins: C-a I"
    echo "  3. Open nvim (plugins auto-install on first launch)"
    echo "     Note: LSPs won't install without dev toolchains — that's expected on servers."
    echo "     nvim still works great for editing scripts, configs, and logs."
    echo ""
    exit 0
fi

# ─── Default install mode ────────────────────────────────
echo "=== dotfiles installer ==="
echo "    --full    multi-distro setup with shell config, nerd font, dev toolchain"
echo "    --server  lightweight server install (tmux, nvim, fzf, bat, btop)"
echo ""

# Detect OS
OS="$(uname -s)"
echo "OS: $OS"

# Ensure curl and git are available (fresh Ubuntu may not have them)
if [ "$OS" = "Linux" ] && command -v apt-get &>/dev/null; then
    for dep in curl git; do
        if ! command -v "$dep" &>/dev/null; then
            echo "Installing $dep..."
            sudo apt-get update -qq && sudo apt-get install -y -qq "$dep"
        fi
    done
fi

# ─── Backup existing configs ─────────────────────────────
BACKUP_DIR="$HOME/.config/dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

backup_if_exists() {
    local path="$1"
    local name="$2"
    if [ -d "$path" ] && [ ! -d "$path/.git" ]; then
        echo "Found existing $name config (not a git repo)"
        read -rp "  Back up $path before replacing? [Y/n] " answer
        answer="${answer:-Y}"
        if [[ "$answer" =~ ^[Yy] ]]; then
            mkdir -p "$BACKUP_DIR"
            cp -r "$path" "$BACKUP_DIR/$name"
            echo "  Backed up to $BACKUP_DIR/$name"
        fi
    elif [ -d "$path/.git" ]; then
        # Check if it's our repo or someone else's
        local remote
        remote=$(cd "$path" && git remote get-url origin 2>/dev/null || echo "")
        if [ -n "$remote" ] && ! echo "$remote" | grep -q "irlm"; then
            echo "Found existing $name config (git repo: $remote)"
            read -rp "  Back up $path before replacing? [Y/n] " answer
            answer="${answer:-Y}"
            if [[ "$answer" =~ ^[Yy] ]]; then
                mkdir -p "$BACKUP_DIR"
                cp -r "$path" "$BACKUP_DIR/$name"
                echo "  Backed up to $BACKUP_DIR/$name"
            fi
        fi
    fi
}

backup_if_exists "$HOME/.config/tmux" "tmux"
backup_if_exists "$HOME/.config/nvim" "nvim"

# Backup .zshrc if it exists
if [ -f "$HOME/.zshrc" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$HOME/.zshrc" "$BACKUP_DIR/.zshrc"
    echo "Backed up .zshrc to $BACKUP_DIR/.zshrc"
fi

# ─── Install dependencies ────────────────────────────────
echo ""
echo "Installing dependencies..."

if [ "$OS" = "Darwin" ]; then
    if ! command -v brew &>/dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
    fi
    for pkg in tmux neovim lazygit lazydocker fzf zoxide bat gh fastfetch btop oh-my-posh node go; do
        if brew list "$pkg" &>/dev/null; then
            echo "  $pkg already installed"
        else
            echo "  Installing $pkg..."
            brew install "$pkg"
        fi
    done
elif [ "$OS" = "Linux" ]; then
    sudo apt-get update
    sudo apt-get install -y tmux fzf bat snapd nodejs npm golang-go default-jdk python3 build-essential
    # neovim via appimage (apt version is too old for LazyVim, needs 0.10+)
    install_nvim=false
    if ! command -v nvim &>/dev/null; then
        install_nvim=true
    else
        nvim_ver=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        nvim_major=$(echo "$nvim_ver" | cut -d. -f1)
        nvim_minor=$(echo "$nvim_ver" | cut -d. -f2)
        if [ "$nvim_major" -eq 0 ] && [ "$nvim_minor" -lt 10 ]; then
            echo "Found neovim $nvim_ver (too old, need 0.10+). Upgrading..."
            install_nvim=true
        fi
    fi
    if $install_nvim; then
        echo "Installing neovim via appimage..."
        sudo apt-get remove -y neovim neovim-runtime 2>/dev/null || true
        curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$(uname -m).appimage" -o /tmp/nvim.appimage
        chmod +x /tmp/nvim.appimage
        sudo mv /tmp/nvim.appimage /usr/local/bin/nvim
    fi
    # lazygit
    if ! command -v lazygit &>/dev/null; then
        LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
        curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
        sudo tar xf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit
    fi
    # lazydocker
    if ! command -v lazydocker &>/dev/null; then
        LAZYDOCKER_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
        curl -Lo /tmp/lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz"
        sudo tar xf /tmp/lazydocker.tar.gz -C /usr/local/bin lazydocker
    fi
    # zoxide
    command -v zoxide &>/dev/null || curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    # oh-my-posh
    command -v oh-my-posh &>/dev/null || curl -s https://ohmyposh.dev/install.sh | bash -s
fi

# ─── Neovim language toolchain ───────────────────────────
echo ""
echo "Setting up neovim language dependencies..."

# Rust: install rustup + rust-analyzer if not present
if command -v rustup &>/dev/null; then
    if ! rustup component list 2>/dev/null | grep -q 'rust-analyzer.*installed'; then
        echo "Adding rust-analyzer component..."
        rustup component add rust-analyzer
    fi
elif ! command -v rustc &>/dev/null; then
    echo "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
    rustup component add rust-analyzer
fi

# Scala: install coursier + metals if not present
if ! command -v metals &>/dev/null; then
    if [ "$OS" = "Darwin" ]; then
        if ! command -v cs &>/dev/null; then
            brew install coursier/formulas/coursier
        fi
        cs install metals 2>/dev/null || true
    elif command -v cs &>/dev/null || command -v coursier &>/dev/null; then
        $(command -v cs || command -v coursier) install metals 2>/dev/null || true
    elif command -v java &>/dev/null; then
        echo "Installing Coursier + Metals..."
        curl -fLo "$HOME/.local/bin/cs" "https://github.com/coursier/coursier/releases/latest/download/coursier" 2>/dev/null || true
        if [ -f "$HOME/.local/bin/cs" ] && [ -s "$HOME/.local/bin/cs" ]; then
            chmod +x "$HOME/.local/bin/cs"
            "$HOME/.local/bin/cs" install metals 2>/dev/null || true
        fi
    fi
fi

# ─── Docker ──────────────────────────────────────────────
echo ""
echo "Setting up Docker..."

if command -v docker &>/dev/null; then
    echo "Docker already installed"
else
    if [ "$OS" = "Darwin" ]; then
        brew install --cask docker
        open -a Docker
        echo "Docker Desktop installed and starting..."
    elif [ "$OS" = "Linux" ]; then
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        sudo systemctl enable docker 2>/dev/null || true
        sudo systemctl start docker 2>/dev/null || true
        echo "Docker installed (log out and back in for group changes)"
    fi
fi

# ─── Clone configs ────────────────────────────────────────
echo ""
echo "Setting up configs..."

REPO_BASE="https://github.com/irlm"

clone_or_pull() {
    local repo="$1"
    local dest="$2"
    local name="$3"
    local remote

    if [ -d "$dest/.git" ]; then
        remote=$(cd "$dest" && git remote get-url origin 2>/dev/null || echo "")
        if echo "$remote" | grep -q "irlm"; then
            echo "$name config exists, pulling..."
            cd "$dest" && git pull --ff-only
            return
        fi
    fi

    echo "Cloning $name config..."
    rm -rf "$dest"
    git clone "$REPO_BASE/$repo" "$dest"
}

clone_or_pull "tmux.git" "$HOME/.config/tmux" "tmux"
clone_or_pull "nvim.git" "$HOME/.config/nvim" "nvim"

# ─── TPM plugins ──────────────────────────────────────────
echo ""
echo "Installing tmux plugins..."
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi
# Install new plugins, update existing, remove unused
"$TPM_DIR/bin/install_plugins" 2>/dev/null || true
"$TPM_DIR/bin/update_plugins" all 2>/dev/null || true
"$TPM_DIR/bin/clean_plugins" 2>/dev/null || true

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
mkdir -p "$HOME/.local/bin"

# ─── Done ─────────────────────────────────────────────────
echo ""
echo "=== Install complete! ==="
echo ""
echo "Next steps:"
echo "  1. Open a new terminal"
echo "  2. Run: tmux"
echo "  3. Press C-a I to install tmux plugins"
echo "  4. Run: nvim (plugins + LSPs auto-install on first launch)"
echo ""
echo "Installed toolchains: Rust, Go, Python, Node.js, Java, Scala (Metals), Docker"
echo ""
echo "For the full setup (shell config, nerd font, multi-distro):"
echo "  bash install.sh --full"
echo ""
