#!/usr/bin/env bash
# ─── Dotfiles Installer (macOS / Linux) ──────────────────
# Quick install:  curl -sL .../install.sh | bash
# Full setup:     bash install.sh --full
# Server (light): bash install.sh --server
#
# --full:   multi-distro, shell config, nerd font, zsh plugins, dev toolchain, Docker
# --server: minimal — tmux, neovim (no LSPs), fzf, bat, btop, ripgrep
# --herdr:  also install Herdr (herdr.dev) with this repo's keys, popups and plugin;
#           an already installed Herdr is configured without the flag
set -euo pipefail

MODE="default"
WANT_HERDR=0
for arg in "$@"; do
    case "$arg" in
        --full|-f)   MODE="full" ;;
        --server|-s) MODE="server" ;;
        --herdr)     WANT_HERDR=1 ;;   # also install Herdr and configure it from this repo
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
        curl -fsSL --connect-timeout 10 "$url" -o "$dest"
    else
        wget -qO "$dest" "$url"
    fi
}

# ─── Helper: install binary from GitHub release ─────────
# Usage: install_gh_binary <repo> <binary> <pattern>
# Installs to ~/.local/bin. Returns 0 on success.
install_gh_binary() {
    local repo="$1" binary="$2" pattern="$3"
    command -v "$binary" &>/dev/null && return 0
    echo "  Installing $binary from GitHub ($repo)..."
    local url
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | grep "browser_download_url" \
        | grep -i "$pattern" \
        | grep -vi "sha256\|\.sig\|\.asc" \
        | head -1 | cut -d '"' -f 4) || true
    [ -z "$url" ] && echo "    Could not find release for $binary" && return 1
    local tmp; tmp=$(mktemp -d)
    if [[ "$url" == *.tbz ]] || [[ "$url" == *.tar.bz2 ]]; then
        curl -fsSL "$url" | tar xj -C "$tmp"
    elif [[ "$url" == *.zip ]]; then
        curl -fsSL "$url" -o "$tmp/archive.zip" && unzip -qo "$tmp/archive.zip" -d "$tmp"
    else
        curl -fsSL "$url" | tar xz -C "$tmp"
    fi
    local found
    found=$(find "$tmp" -name "$binary" -type f 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        chmod +x "$found"
        mkdir -p "$HOME/.local/bin"
        mv "$found" "$HOME/.local/bin/$binary"
        echo "    $binary installed to ~/.local/bin"
    else
        echo "    Binary '$binary' not found in release archive"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
}

# Load shared assets locally, or bootstrap them for the curl one-liner.
INSTALL_ASSETS="${TMUX_INSTALL_ASSETS:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
if [ ! -f "$INSTALL_ASSETS/scripts/install-lib.sh" ] || [ ! -f "$INSTALL_ASSETS/tools.tsv" ]; then
    ensure_curl
    INSTALL_ASSETS=$(mktemp -d)
    trap 'rm -rf -- "$INSTALL_ASSETS"' EXIT
    mkdir -p "$INSTALL_ASSETS/scripts"
    download "https://raw.githubusercontent.com/irlm/tmux/main/scripts/install-lib.sh" "$INSTALL_ASSETS/scripts/install-lib.sh"
    download "https://raw.githubusercontent.com/irlm/tmux/main/tools.tsv" "$INSTALL_ASSETS/tools.tsv"
fi
# shellcheck source=scripts/install-lib.sh
source "$INSTALL_ASSETS/scripts/install-lib.sh"
install_target_shell >/dev/null

# ─── Full setup mode ─────────────────────────────────────
if [ "$MODE" = "full" ]; then
    echo "=== Full setup mode ==="
    echo ""
    ensure_curl
    TMPSCRIPT=$(mktemp)
    download "https://raw.githubusercontent.com/irlm/tmux/main/setup.sh" "$TMPSCRIPT"
    TMUX_INSTALL_ASSETS="$INSTALL_ASSETS" bash "$TMPSCRIPT"
    rm -f -- "$TMPSCRIPT"
    exit 0
fi

# ─── Server (light) mode ─────────────────────────────────
if [ "$MODE" = "server" ]; then
    echo "=== Server (light) install ==="
    echo ""
    OS="$(uname -s)"

    # Ensure basics (only essentials from package managers)
    if [ "$OS" = "Linux" ]; then
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq curl git tmux htop jq build-essential w3m python3 fd-find
            # neovim (apt version is too old for LazyVim on Ubuntu < 24.04)
            if ! command -v nvim &>/dev/null || [ "$(nvim --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f2)" -lt 10 ] 2>/dev/null; then
                echo "  Installing neovim via appimage..."
                sudo apt-get remove -y neovim neovim-runtime 2>/dev/null || true
                NVIM_ARCH=$(uname -m); [ "$NVIM_ARCH" = "aarch64" ] && NVIM_ARCH="arm64"
                curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.appimage" -o /tmp/nvim.appimage
                chmod +x /tmp/nvim.appimage
                sudo mv /tmp/nvim.appimage /usr/local/bin/nvim
            fi
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y -q curl git tmux jq neovim gcc make w3m python3 fd-find
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm --needed curl git tmux jq neovim base-devel w3m python fd
        elif command -v zypper &>/dev/null; then
            sudo zypper install -y curl git tmux jq neovim gcc make w3m python3
        fi

        # GitHub-first installs (latest versions, package manager fallback)
        ARCH=$(uname -m)
        [ "$ARCH" = "aarch64" ] && GH_ARCH_GO="arm64" || GH_ARCH_GO="amd64"
        mkdir -p "$HOME/.local/bin"
        export PATH="$HOME/.local/bin:$PATH"

        install_gh_binary "junegunn/fzf" "fzf" "linux_${GH_ARCH_GO}.*\\.tar\\.gz" || true
        install_gh_binary "BurntSushi/ripgrep" "rg" "${ARCH}.*linux.*\\.tar\\.gz" || true
        install_gh_binary "sharkdp/fd" "fd" "${ARCH}.*linux.*musl.*\\.tar\\.gz" || true
        install_gh_binary "sharkdp/bat" "bat" "${ARCH}.*linux.*musl.*\\.tar\\.gz" || true
        install_gh_binary "aristocratos/btop" "btop" "${ARCH}.*linux.*musl.*\\.tbz" || true
        # fastfetch names x86_64 assets "amd64" but keeps "aarch64" for arm
        [ "$ARCH" = "x86_64" ] && FF_ARCH="amd64" || FF_ARCH="$ARCH"
        install_gh_binary "fastfetch-cli/fastfetch" "fastfetch" "linux-${FF_ARCH}[^-]*\\.tar\\.gz" || true
        # C-a g is a headline binding; one static binary is worth it on a server.
        # lazygit/lazydocker assets: Linux_x86_64 and Linux_arm64
        [ "$ARCH" = "aarch64" ] && LZ_ARCH="arm64" || LZ_ARCH="$ARCH"
        install_gh_binary "jesseduffield/lazygit" "lazygit" "Linux_${LZ_ARCH}\\.tar\\.gz" || true

    elif [ "$OS" = "Darwin" ]; then
        if ! command -v brew &>/dev/null; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
        fi
        install_brew_tools server "$INSTALL_ASSETS"
    fi

    if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    fi

    # zoxide (official install script)
    if ! command -v zoxide &>/dev/null; then
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    fi

    # tlrc (architecture-matched release; Homebrew on macOS)
    if ! command -v tldr &>/dev/null && ! command -v tlrc &>/dev/null; then
        ARCH=$(uname -m)
        if [ "$OS" = Darwin ]; then
            brew install tlrc
        elif [ "$OS" = Linux ]; then
            install_gh_binary "tldr-pages/tlrc" "tldr" "${ARCH}.*linux.*musl.*\\.tar\\.gz" || true
        elif command -v cargo &>/dev/null; then
            echo "  Installing tlrc via cargo (no binary for $ARCH)..."
            cargo install tlrc 2>/dev/null || true
        fi
    fi

    clone_config tmux "$HOME/.config/tmux"
    clone_config nvim "$HOME/.config/nvim"

    install_tmux_plugins "$HOME/.config/tmux"

    install_shell_integration server

    # Mark nvim as server mode (disables LSPs, heavy treesitter, Mason packages)
    touch "$HOME/.config/nvim/.server"

    # Data dirs
    mkdir -p "$HOME/.local/share/tmux" "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    echo ""
    check_install_tools server "$INSTALL_ASSETS"
    echo "=== Server install complete! ==="
    echo ""
    echo "Config installed. Run ~/.config/tmux/update.sh --check to verify all tools."
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
echo "    --herdr   also install Herdr and configure it from this repo"
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

# Backup the shell config this run will append to, if it exists
RC_TO_BACKUP="$(shell_rc_file)"
if [ -f "$RC_TO_BACKUP" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$RC_TO_BACKUP" "$BACKUP_DIR/$(basename "$RC_TO_BACKUP")"
    echo "Backed up $(basename "$RC_TO_BACKUP") to $BACKUP_DIR/"
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
    install_brew_tools desktop "$INSTALL_ASSETS"
    for pkg in node go openjdk; do
        if brew list "$pkg" &>/dev/null; then
            echo "  $pkg already installed"
        else
            echo "  Installing $pkg..."
            brew install "$pkg" || echo "    Failed to install $pkg (continuing)"
        fi
    done
elif [ "$OS" = "Linux" ]; then
    sudo apt-get update
    sudo apt-get install -y tmux nodejs npm golang-go default-jdk python3 build-essential w3m jq
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
        NVIM_ARCH=$(uname -m); [ "$NVIM_ARCH" = "aarch64" ] && NVIM_ARCH="arm64"
        curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.appimage" -o /tmp/nvim.appimage
        chmod +x /tmp/nvim.appimage
        sudo mv /tmp/nvim.appimage /usr/local/bin/nvim
    fi

    # GitHub-first installs (latest versions)
    ARCH=$(uname -m)
    [ "$ARCH" = "aarch64" ] && GH_ARCH_GO="arm64" || GH_ARCH_GO="amd64"
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    install_gh_binary "junegunn/fzf" "fzf" "linux_${GH_ARCH_GO}.*\\.tar\\.gz" || true
    install_gh_binary "BurntSushi/ripgrep" "rg" "${ARCH}.*linux.*\\.tar\\.gz" || true
    install_gh_binary "sharkdp/fd" "fd" "${ARCH}.*linux.*musl.*\\.tar\\.gz" || true
    install_gh_binary "sharkdp/bat" "bat" "${ARCH}.*linux.*musl.*\\.tar\\.gz" || true
    install_gh_binary "aristocratos/btop" "btop" "${ARCH}.*linux.*musl.*\\.tbz" || true
    [ "$ARCH" = "x86_64" ] && FF_ARCH="amd64" || FF_ARCH="$ARCH"   # fastfetch: amd64 but aarch64
    install_gh_binary "fastfetch-cli/fastfetch" "fastfetch" "linux-${FF_ARCH}[^-]*\\.tar\\.gz" || true
    [ "$ARCH" = "aarch64" ] && LZ_ARCH="arm64" || LZ_ARCH="$ARCH"   # lazygit/lazydocker: x86_64 / arm64
    install_gh_binary "jesseduffield/lazygit" "lazygit" "Linux_${LZ_ARCH}\\.tar\\.gz" || true
    install_gh_binary "jesseduffield/lazydocker" "lazydocker" "Linux_${LZ_ARCH}\\.tar\\.gz" || true
    install_gh_binary "cli/cli" "gh" "linux_${GH_ARCH_GO}.*\\.tar\\.gz" || true

    # zoxide (official install script)
    command -v zoxide &>/dev/null || curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    # oh-my-posh (official install script)
    command -v oh-my-posh &>/dev/null || curl -s https://ohmyposh.dev/install.sh | bash -s
    # tlrc (GitHub release)
    if ! command -v tldr &>/dev/null; then
        install_gh_binary "tldr-pages/tlrc" "tldr" "${ARCH}.*linux.*musl.*\\.tar\\.gz" || true
    fi
fi

# ─── gh extensions ────────────────────────────────────────
# `gh dash` (the C-a G popup) ships as an extension, not with gh itself —
# installing the GitHub CLI alone leaves that binding dead.
if command -v gh &>/dev/null; then
    if gh extension list 2>/dev/null | grep "dlvhdr/gh-dash" >/dev/null; then
        echo "  gh-dash already installed"
    else
        echo "  Installing gh-dash extension..."
        if ! gh extension install dlvhdr/gh-dash; then
            echo "    Failed to install gh-dash. Run 'gh auth login', then:"
            echo "      gh extension install dlvhdr/gh-dash"
        fi
    fi
fi

# ─── Clone configs ────────────────────────────────────────
# Done early — so configs land even if later optional installs fail
# (Docker cask, rust-analyzer, etc. often fail for non-admin users).
echo ""
echo "Setting up configs..."


clone_config tmux "$HOME/.config/tmux"
clone_config nvim "$HOME/.config/nvim"
rm -f -- "$HOME/.config/nvim/.server"

# ─── TPM plugins ──────────────────────────────────────────
echo ""
echo "Installing tmux plugins..."
install_tmux_plugins "$HOME/.config/tmux"

# ─── Neovim language toolchain ───────────────────────────
echo ""
echo "Setting up neovim language dependencies..."

# Rust: install rustup + rust-analyzer if not present (non-fatal)
if command -v rustup &>/dev/null; then
    if ! rustup component list 2>/dev/null | grep 'rust-analyzer.*installed' >/dev/null; then
        echo "Adding rust-analyzer component..."
        rustup component add rust-analyzer || echo "  Skipped rust-analyzer (continuing)"
    fi
elif ! command -v rustc &>/dev/null; then
    echo "Installing Rust via rustup..."
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
        [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
        rustup component add rust-analyzer || true
    else
        echo "  Skipped Rust install (continuing)"
    fi
fi

# Keg-only openjdk and Coursier's bin directory are on no default PATH, so
# without this the checks below (and metals itself) cannot see them.
for _p in /opt/homebrew/opt/openjdk/bin /usr/local/opt/openjdk/bin \
          "$HOME/Library/Application Support/Coursier/bin" "$HOME/.local/share/coursier/bin"; do
    [ -d "$_p" ] && export PATH="$_p:$PATH"
done
unset _p

# Scala: install coursier + metals if not present
if ! command -v metals &>/dev/null; then
    if [ "$OS" = "Darwin" ]; then
        if ! command -v cs &>/dev/null; then
            brew install coursier/formulas/coursier
        fi
        cs install metals 2>/dev/null || true
    elif command -v cs &>/dev/null || command -v coursier &>/dev/null; then
        $(command -v cs || command -v coursier) install metals 2>/dev/null || true
    elif java -version &>/dev/null; then
        echo "Installing Coursier + Metals..."
        curl -fLo "$HOME/.local/bin/cs" "https://github.com/coursier/coursier/releases/latest/download/coursier" 2>/dev/null || true
        if [ -f "$HOME/.local/bin/cs" ] && [ -s "$HOME/.local/bin/cs" ]; then
            chmod +x "$HOME/.local/bin/cs"
            "$HOME/.local/bin/cs" install metals 2>/dev/null || true
        fi
    fi
fi

# ─── Docker (optional — non-fatal) ───────────────────────
# Cask install on macOS needs admin; non-admin secondary users will skip.
echo ""
echo "Setting up Docker..."

if command -v docker &>/dev/null; then
    echo "Docker already installed"
else
    if [ "$OS" = "Darwin" ]; then
        if brew install --cask docker 2>/dev/null; then
            open -a Docker 2>/dev/null || true
            echo "Docker Desktop installed and starting..."
        else
            echo "  Skipped Docker (cask install failed — needs admin? install manually if needed)"
        fi
    elif [ "$OS" = "Linux" ]; then
        echo "Installing Docker..."
        if curl -fsSL https://get.docker.com | sh; then
            sudo usermod -aG docker "$USER" 2>/dev/null || true
            sudo systemctl enable docker 2>/dev/null || true
            sudo systemctl start docker 2>/dev/null || true
            echo "Docker installed (log out and back in for group changes)"
        else
            echo "  Skipped Docker (install failed — install manually if needed)"
        fi
    fi
fi

# ─── Shell config ─────────────────────────────────────────
install_shell_integration desktop

# ─── Herdr (optional) ────────────────────────────────────
install_herdr_workbench "$INSTALL_ASSETS" "$WANT_HERDR" || echo "  Herdr setup incomplete; rerun: bash install.sh --herdr"

# ─── Create data dirs ─────────────────────────────────────
mkdir -p "$HOME/.local/share/tmux"
mkdir -p "$HOME/.local/bin"

# ─── Done ─────────────────────────────────────────────────
echo ""
check_install_tools desktop "$INSTALL_ASSETS"
echo "=== Install complete! ==="
echo ""
echo "Next steps:"
echo "  1. Open a new terminal"
echo "  2. Run: tmux"
echo "  3. Press C-a I to install tmux plugins"
echo "  4. Run: nvim (plugins + LSPs auto-install on first launch)"
if command -v herdr >/dev/null 2>&1; then echo "  5. Or run: herdr (same keys, agent sidebar; see docs/herdr.md)"; fi
echo ""
echo "Installed toolchains: Rust, Go, Python, Node.js, Java, Scala (Metals), Docker"
echo ""
echo "For the full setup (shell config, nerd font, multi-distro):"
echo "  bash install.sh --full"
echo ""
