#!/bin/bash
# ─── Tmux + Shell Bootstrap (Cross-Platform) ────────────
# Supports: macOS, Ubuntu/Debian, Fedora/RHEL, Arch/Manjaro, WSL
#
# Run on any machine:  curl -sL <raw-url> | bash
# Or locally:          bash ~/.config/tmux/setup.sh
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERR]${NC} $1"; }

# ─── OS / Distro Detection ─────────────────────────────
OS=""
DISTRO=""
PKG_MGR=""
IS_WSL=false
ARCH="$(uname -m)"

detect_os() {
  case "$(uname -s)" in
    Darwin)
      OS="macos"
      PKG_MGR="brew"
      ;;
    Linux)
      OS="linux"
      # WSL detection
      if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL=true
      fi
      # Distro detection via /etc/os-release
      if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}" in
          ubuntu|debian|linuxmint|pop|elementary|zorin|kali)
            DISTRO="debian" ; PKG_MGR="apt" ;;
          fedora|rhel|centos|rocky|alma|nobara)
            DISTRO="fedora" ; PKG_MGR="dnf" ;;
          arch|manjaro|endeavouros|garuda|artix)
            DISTRO="arch"   ; PKG_MGR="pacman" ;;
          opensuse*|sles)
            DISTRO="suse"   ; PKG_MGR="zypper" ;;
          *)
            # Try ID_LIKE as fallback
            case "${ID_LIKE:-}" in
              *debian*|*ubuntu*) DISTRO="debian" ; PKG_MGR="apt" ;;
              *fedora*|*rhel*)   DISTRO="fedora" ; PKG_MGR="dnf" ;;
              *arch*)            DISTRO="arch"   ; PKG_MGR="pacman" ;;
              *suse*)            DISTRO="suse"   ; PKG_MGR="zypper" ;;
              *)
                err "Unsupported distro: ${ID:-unknown} (ID_LIKE=${ID_LIKE:-none})"
                err "Supported: Ubuntu/Debian, Fedora/RHEL, Arch/Manjaro, openSUSE"
                exit 1
                ;;
            esac
            ;;
        esac
      else
        err "Cannot detect Linux distribution (/etc/os-release not found)"
        exit 1
      fi
      ;;
    *)
      err "Unsupported OS: $(uname -s)"
      exit 1
      ;;
  esac

  info "Detected: OS=$OS DISTRO=$DISTRO PKG_MGR=$PKG_MGR WSL=$IS_WSL ARCH=$ARCH"
}

detect_os

# ─── Package Manager Helpers ───────────────────────────
pkg_update() {
  case "$PKG_MGR" in
    apt)    sudo apt-get update -qq ;;
    dnf)    sudo dnf check-update -q || true ;;
    pacman) sudo pacman -Sy --noconfirm ;;
    zypper) sudo zypper refresh -q ;;
  esac
}

pkg_install() {
  local pkg="$1"
  case "$PKG_MGR" in
    brew)   brew install "$pkg" ;;
    apt)    sudo apt-get install -y -qq "$pkg" ;;
    dnf)    sudo dnf install -y -q "$pkg" ;;
    pacman) sudo pacman -S --noconfirm --needed "$pkg" ;;
    zypper) sudo zypper install -y "$pkg" ;;
  esac
}

pkg_is_installed() {
  local pkg="$1"
  case "$PKG_MGR" in
    brew)   brew list "$pkg" &>/dev/null ;;
    apt)    dpkg -s "$pkg" &>/dev/null 2>&1 ;;
    dnf)    rpm -q "$pkg" &>/dev/null 2>&1 ;;
    pacman) pacman -Q "$pkg" &>/dev/null 2>&1 ;;
    zypper) rpm -q "$pkg" &>/dev/null 2>&1 ;;
  esac
}

# Install a binary from GitHub releases
# Usage: install_from_github <owner/repo> <binary-name> <tar-pattern>
install_from_github() {
  local repo="$1" binary="$2" pattern="$3"
  local url

  if command -v "$binary" &>/dev/null; then
    ok "$binary already installed"
    return 0
  fi

  info "Installing $binary from GitHub ($repo)..."
  url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | grep "browser_download_url" \
    | grep -i "$pattern" \
    | head -1 \
    | cut -d '"' -f 4) || true

  if [ -z "$url" ]; then
    warn "Could not find $binary release for $ARCH — skipping"
    return 1
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  cd "$tmpdir"

  if [[ "$url" == *.tar.gz ]] || [[ "$url" == *.tgz ]]; then
    curl -fsSL "$url" | tar xz
  elif [[ "$url" == *.zip ]]; then
    curl -fsSL "$url" -o archive.zip && unzip -q archive.zip
  else
    curl -fsSL "$url" -o "$binary"
  fi

  # Find the binary and install it
  local found
  found=$(find "$tmpdir" -name "$binary" -type f 2>/dev/null | head -1)
  if [ -n "$found" ]; then
    chmod +x "$found"
    mkdir -p "$HOME/.local/bin"
    mv "$found" "$HOME/.local/bin/$binary"
    ok "$binary installed to ~/.local/bin"
  else
    warn "Binary $binary not found in release archive — skipping"
  fi

  cd - >/dev/null
  rm -rf "$tmpdir"
}

# Map architecture names for GitHub releases
gh_arch() {
  case "$ARCH" in
    x86_64)  echo "${1:-x86_64}" ;;
    aarch64|arm64) echo "${2:-arm64}" ;;
    *) echo "$ARCH" ;;
  esac
}

# ─── Prerequisites ─────────────────────────────────────
install_prerequisites() {
  info "Checking prerequisites..."
  mkdir -p "$HOME/.local/bin"

  if [[ "$OS" == "macos" ]]; then
    # Homebrew
    if ! command -v brew &>/dev/null; then
      info "Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
      ok "Homebrew installed"
    else
      ok "Homebrew already installed"
    fi
  else
    # Linux prerequisites
    info "Updating package index..."
    pkg_update

    # Ensure basics
    for dep in git curl wget unzip; do
      if ! command -v "$dep" &>/dev/null; then
        info "Installing $dep..."
        pkg_install "$dep"
      fi
    done

    # Install build tools
    case "$PKG_MGR" in
      apt)    sudo apt-get install -y -qq build-essential ;;
      dnf)    sudo dnf groupinstall -y -q "Development Tools" 2>/dev/null || sudo dnf install -y -q gcc make ;;
      pacman) sudo pacman -S --noconfirm --needed base-devel ;;
      zypper) sudo zypper install -y -t pattern devel_basis ;;
    esac

    # WSL extras
    if $IS_WSL; then
      case "$PKG_MGR" in
        apt) pkg_is_installed wslu || pkg_install wslu ;;
      esac
    fi
  fi
}

install_prerequisites

# ─── Core Packages ─────────────────────────────────────
install_core_packages() {
  info "Installing core packages..."

  if [[ "$OS" == "macos" ]]; then
    # macOS: everything via Homebrew
    local BREW_PACKAGES=(
      tmux fzf lazygit lazydocker btop fastfetch gh
      ripgrep fd bat eza zoxide tlrc jq
    )
    for pkg in "${BREW_PACKAGES[@]}"; do
      if brew list "$pkg" &>/dev/null; then
        ok "$pkg already installed"
      else
        info "Installing $pkg..."
        brew install "$pkg"
        ok "$pkg installed"
      fi
    done
    return
  fi

  # ── Linux: per-distro package maps ──
  # Packages available in all distro repos
  local COMMON_PKGS
  case "$PKG_MGR" in
    apt)
      COMMON_PKGS="tmux fzf btop ripgrep fd-find bat jq zoxide"
      ;;
    dnf)
      COMMON_PKGS="tmux fzf btop ripgrep fd-find bat jq zoxide"
      ;;
    pacman)
      COMMON_PKGS="tmux fzf btop ripgrep fd bat jq zoxide lazygit fastfetch github-cli eza"
      ;;
    zypper)
      COMMON_PKGS="tmux fzf btop ripgrep fd bat jq zoxide"
      ;;
  esac

  for pkg in $COMMON_PKGS; do
    if pkg_is_installed "$pkg"; then
      ok "$pkg already installed"
    else
      info "Installing $pkg..."
      pkg_install "$pkg" || warn "Failed to install $pkg — may need manual install"
      ok "$pkg installed"
    fi
  done

  # ── Debian: symlink renamed binaries ──
  if [[ "$DISTRO" == "debian" ]]; then
    [ -x /usr/bin/fdfind ] && [ ! -e "$HOME/.local/bin/fd" ] && \
      ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd" && ok "Symlinked fd -> fdfind"
    [ -x /usr/bin/batcat ] && [ ! -e "$HOME/.local/bin/bat" ] && \
      ln -sf /usr/bin/batcat "$HOME/.local/bin/bat" && ok "Symlinked bat -> batcat"
  fi

  # ── Packages needing special handling on some distros ──

  # gh (GitHub CLI)
  if [[ "$PKG_MGR" != "pacman" ]]; then
    if ! command -v gh &>/dev/null; then
      case "$PKG_MGR" in
        apt)
          info "Installing GitHub CLI..."
          curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
          sudo apt-get update -qq && sudo apt-get install -y -qq gh
          ok "gh installed"
          ;;
        dnf)
          sudo dnf install -y -q 'dnf-command(config-manager)' 2>/dev/null || true
          sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null || true
          sudo dnf install -y -q gh
          ok "gh installed"
          ;;
        zypper)
          sudo zypper install -y gh || install_from_github "cli/cli" "gh" "linux_$(gh_arch amd64 arm64).*\\.tar\\.gz"
          ;;
      esac
    else
      ok "gh already installed"
    fi
  fi

  # lazygit (not in Debian/Fedora/SUSE repos)
  if [[ "$PKG_MGR" != "pacman" ]]; then
    install_from_github "jesseduffield/lazygit" "lazygit" "Linux_$(gh_arch x86_64 arm64).*\\.tar\\.gz"
  fi

  # fastfetch (not in older distro repos)
  if ! command -v fastfetch &>/dev/null; then
    # Try repo first
    pkg_install fastfetch 2>/dev/null || {
      # Fallback: download .deb/.rpm from GitHub and install with system tools
      info "Installing fastfetch from GitHub release..."
      local ff_url ff_tmp
      ff_tmp=$(mktemp -d)
      case "$PKG_MGR" in
        apt)
          ff_url=$(curl -fsSL "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest" \
            | grep "browser_download_url" \
            | grep -i "linux-$(gh_arch amd64 aarch64).*\\.deb" \
            | grep -v "source" | head -1 | cut -d '"' -f 4) || true
          if [ -n "$ff_url" ]; then
            curl -fsSL "$ff_url" -o "$ff_tmp/fastfetch.deb"
            sudo dpkg -i "$ff_tmp/fastfetch.deb" 2>/dev/null && sudo apt-get install -f -y -qq 2>/dev/null
            ok "fastfetch installed"
          fi
          ;;
        dnf|zypper)
          ff_url=$(curl -fsSL "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest" \
            | grep "browser_download_url" \
            | grep -i "linux-$(gh_arch amd64 aarch64).*\\.rpm" \
            | grep -v "source" | head -1 | cut -d '"' -f 4) || true
          if [ -n "$ff_url" ]; then
            curl -fsSL "$ff_url" -o "$ff_tmp/fastfetch.rpm"
            sudo rpm -i "$ff_tmp/fastfetch.rpm" 2>/dev/null
            ok "fastfetch installed"
          fi
          ;;
      esac
      rm -rf "$ff_tmp"
    }
  else
    ok "fastfetch already installed"
  fi

  # eza (not in older Debian/Fedora repos)
  if [[ "$PKG_MGR" != "pacman" ]] && ! command -v eza &>/dev/null; then
    case "$PKG_MGR" in
      apt)
        # Try the official eza repo
        if ! pkg_install eza 2>/dev/null; then
          sudo mkdir -p /etc/apt/keyrings
          wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg 2>/dev/null || true
          echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
          sudo apt-get update -qq && sudo apt-get install -y -qq eza
        fi
        ok "eza installed"
        ;;
      dnf)
        pkg_install eza 2>/dev/null || \
          install_from_github "eza-community/eza" "eza" "eza_$(gh_arch x86_64 aarch64).*linux.*gnu\\.tar\\.gz"
        ;;
      zypper)
        pkg_install eza 2>/dev/null || \
          install_from_github "eza-community/eza" "eza" "eza_$(gh_arch x86_64 aarch64).*linux.*gnu\\.tar\\.gz"
        ;;
    esac
  fi

  # tlrc (Rust tldr client — binary is named "tldr" in the archive)
  if ! command -v tldr &>/dev/null && ! command -v tlrc &>/dev/null; then
    info "Installing tlrc from GitHub..."
    local tlrc_url
    tlrc_url=$(curl -fsSL "https://api.github.com/repos/tldr-pages/tlrc/releases/latest" \
      | grep "browser_download_url" \
      | grep -i "$(gh_arch x86_64 aarch64).*linux.*musl.*\\.tar\\.gz" \
      | head -1 | cut -d '"' -f 4) || true
    if [ -n "$tlrc_url" ]; then
      local tlrc_tmp
      tlrc_tmp=$(mktemp -d)
      curl -fsSL "$tlrc_url" | tar xz -C "$tlrc_tmp"
      if [ -f "$tlrc_tmp/tldr" ]; then
        chmod +x "$tlrc_tmp/tldr"
        mkdir -p "$HOME/.local/bin"
        mv "$tlrc_tmp/tldr" "$HOME/.local/bin/tlrc"
        ok "tlrc installed to ~/.local/bin"
      fi
      rm -rf "$tlrc_tmp"
    else
      warn "Could not find tlrc release — skipping"
    fi
  else
    ok "tlrc already installed"
  fi

  # xclip for clipboard support (Linux, non-WSL)
  if [[ "$OS" == "linux" ]] && ! $IS_WSL; then
    if ! command -v xclip &>/dev/null && ! command -v xsel &>/dev/null && ! command -v wl-copy &>/dev/null; then
      info "Installing xclip for clipboard support..."
      pkg_install xclip 2>/dev/null || true
    fi
  fi
}

install_core_packages

# ─── Neovim ───────────────────────────────────────────
install_neovim() {
  if command -v nvim &>/dev/null; then
    local nvim_ver
    nvim_ver=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local nvim_major nvim_minor
    nvim_major=$(echo "$nvim_ver" | cut -d. -f1)
    nvim_minor=$(echo "$nvim_ver" | cut -d. -f2)
    if [ "$nvim_major" -gt 0 ] || [ "$nvim_minor" -ge 10 ]; then
      ok "neovim $nvim_ver already installed"
      return
    fi
    warn "neovim $nvim_ver is too old (need 0.10+), upgrading..."
  fi

  if [[ "$OS" == "macos" ]]; then
    brew install neovim
  else
    case "$PKG_MGR" in
      apt)
        # apt version is usually too old, use snap
        sudo apt-get remove -y neovim neovim-runtime 2>/dev/null || true
        if command -v snap &>/dev/null; then
          sudo snap install nvim --classic
        else
          pkg_install snapd
          sudo snap install nvim --classic
        fi
        ;;
      dnf)    pkg_install neovim ;;
      pacman) pkg_install neovim ;;
      zypper) pkg_install neovim ;;
    esac
  fi
  ok "neovim installed"
}

install_neovim

# ─── Neovim Language Toolchain ────────────────────────
# These are required by the LazyVim language extras (rust, scala, typescript, python, etc.)
install_nvim_lang_deps() {
  info "Installing neovim language toolchain dependencies..."

  # ── Node.js (required by Mason for prettier, typescript-language-server, etc.) ──
  if ! command -v node &>/dev/null; then
    info "Installing Node.js..."
    if [[ "$OS" == "macos" ]]; then
      brew install node
    else
      case "$PKG_MGR" in
        apt)
          # Use NodeSource for recent Node on Debian/Ubuntu
          if ! pkg_install nodejs 2>/dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
          fi
          ;;
        dnf)    pkg_install nodejs ;;
        pacman) pkg_install nodejs npm ;;
        zypper) pkg_install nodejs npm ;;
      esac
    fi
    ok "Node.js installed"
  else
    ok "Node.js already installed ($(node --version))"
  fi

  # ── Rust toolchain + rust-analyzer (for LazyVim rust extra / rustaceanvim) ──
  if command -v rustup &>/dev/null; then
    if ! rustup component list 2>/dev/null | grep -q 'rust-analyzer.*installed'; then
      info "Adding rust-analyzer component..."
      rustup component add rust-analyzer
      ok "rust-analyzer installed"
    else
      ok "rust-analyzer already installed"
    fi
  elif command -v rustc &>/dev/null; then
    ok "Rust installed (system package — install rustup for rust-analyzer)"
  else
    info "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # shellcheck disable=SC1091
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
    rustup component add rust-analyzer
    ok "Rust + rust-analyzer installed"
  fi

  # ── Coursier + Metals (for LazyVim scala extra / nvim-metals) ──
  if ! command -v metals &>/dev/null; then
    if command -v cs &>/dev/null || command -v coursier &>/dev/null; then
      info "Installing Metals LSP via Coursier..."
      local cs_cmd
      cs_cmd=$(command -v cs || command -v coursier)
      "$cs_cmd" install metals 2>/dev/null
      ok "Metals installed"
    elif [[ "$OS" == "macos" ]]; then
      info "Installing Coursier + Metals..."
      brew install coursier/formulas/coursier
      cs install metals 2>/dev/null
      ok "Coursier + Metals installed"
    else
      info "Installing Coursier + Metals..."
      curl -fL https://github.com/coursier/coursier/releases/latest/download/cs-$(gh_arch x86_64 aarch64)-pc-linux.gz | gzip -d > /tmp/cs
      chmod +x /tmp/cs
      mkdir -p "$HOME/.local/bin"
      mv /tmp/cs "$HOME/.local/bin/cs"
      "$HOME/.local/bin/cs" install metals 2>/dev/null
      ok "Coursier + Metals installed"
    fi
  else
    ok "Metals already installed"
  fi

  # ── Go (for gopls, gofumpt, goimports via Mason) ──
  if ! command -v go &>/dev/null; then
    info "Installing Go..."
    if [[ "$OS" == "macos" ]]; then
      brew install go
    else
      case "$PKG_MGR" in
        apt)    pkg_install golang-go ;;
        dnf)    pkg_install golang ;;
        pacman) pkg_install go ;;
        zypper) pkg_install go ;;
      esac
    fi
    ok "Go installed"
  else
    ok "Go already installed ($(go version | cut -d' ' -f3))"
  fi

  # ── Java JDK (for jdtls via Mason) ──
  if ! command -v java &>/dev/null; then
    info "Installing Java JDK..."
    if [[ "$OS" == "macos" ]]; then
      brew install openjdk
    else
      case "$PKG_MGR" in
        apt)    pkg_install default-jdk ;;
        dnf)    pkg_install java-latest-openjdk-devel ;;
        pacman) pkg_install jdk-openjdk ;;
        zypper) pkg_install java-21-openjdk-devel ;;
      esac
    fi
    ok "Java JDK installed"
  else
    ok "Java already installed ($(java -version 2>&1 | head -1))"
  fi

  # ── Python 3 (for pyright, ruff via Mason) ──
  if ! command -v python3 &>/dev/null; then
    info "Installing Python 3..."
    if [[ "$OS" == "macos" ]]; then
      brew install python
    else
      case "$PKG_MGR" in
        apt)    pkg_install python3 python3-venv ;;
        dnf)    pkg_install python3 ;;
        pacman) pkg_install python ;;
        zypper) pkg_install python3 ;;
      esac
    fi
    ok "Python 3 installed"
  else
    ok "Python 3 already installed ($(python3 --version))"
  fi
}

install_nvim_lang_deps

# ─── Docker ───────────────────────────────────────────
install_docker() {
  if command -v docker &>/dev/null; then
    ok "Docker already installed ($(docker --version | cut -d' ' -f3 | tr -d ','))"
  else
    info "Installing Docker..."
    if [[ "$OS" == "macos" ]]; then
      brew install --cask docker
      ok "Docker Desktop installed — launch it from Applications"
    else
      # Linux: official Docker install script
      curl -fsSL https://get.docker.com | sh
      # Add current user to docker group
      sudo usermod -aG docker "$USER" 2>/dev/null || true
      sudo systemctl enable docker 2>/dev/null || true
      sudo systemctl start docker 2>/dev/null || true
      ok "Docker installed (log out and back in for group changes)"
    fi
  fi

  # lazydocker (Linux — macOS gets it via brew in core packages)
  if [[ "$OS" == "linux" ]] && ! command -v lazydocker &>/dev/null; then
    install_from_github "jesseduffield/lazydocker" "lazydocker" "Linux_$(gh_arch x86_64 arm64).*\\.tar\\.gz"
  fi
}

install_docker

# ─── Oh My Posh ────────────────────────────────────────
install_oh_my_posh() {
  if command -v oh-my-posh &>/dev/null; then
    ok "oh-my-posh already installed"
    return
  fi

  if [[ "$OS" == "macos" ]]; then
    brew install oh-my-posh
  else
    info "Installing Oh My Posh..."
    curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
  fi
  ok "oh-my-posh installed"
}

install_oh_my_posh

# ─── Nerd Font ─────────────────────────────────────────
install_nerd_font() {
  if [[ "$OS" == "macos" ]]; then
    if ! brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
      info "Installing JetBrains Mono Nerd Font..."
      brew install --cask font-jetbrains-mono-nerd-font
      ok "Nerd Font installed — set it as your terminal font"
    else
      ok "Nerd Font already installed"
    fi
    return
  fi

  # WSL: fonts must be installed on Windows side
  if $IS_WSL; then
    warn "WSL detected — Nerd Font must be installed on Windows"
    warn "Download from: https://github.com/ryanoasis/nerd-fonts/releases"
    warn "Install 'JetBrains Mono Nerd Font' and set it in your Windows terminal"
    return
  fi

  # Linux: download to ~/.local/share/fonts
  local FONT_DIR="$HOME/.local/share/fonts"
  if ls "$FONT_DIR"/JetBrains*Nerd* &>/dev/null 2>&1; then
    ok "Nerd Font already installed"
    return
  fi

  info "Installing JetBrains Mono Nerd Font..."
  mkdir -p "$FONT_DIR"
  local FONT_VERSION="v3.3.0"
  local tmpfile
  tmpfile=$(mktemp)
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${FONT_VERSION}/JetBrainsMono.tar.xz" -o "$tmpfile"
  tar -xf "$tmpfile" -C "$FONT_DIR"
  rm -f "$tmpfile"
  fc-cache -f "$FONT_DIR" 2>/dev/null || true
  ok "Nerd Font installed — set it as your terminal font"
}

install_nerd_font

# ─── WSL Clipboard ─────────────────────────────────────
if $IS_WSL; then
  if ! command -v win32yank.exe &>/dev/null; then
    info "Installing win32yank for WSL clipboard..."
    tmpdir=$(mktemp -d)
    curl -fsSL "https://github.com/equalsraf/win32yank/releases/download/v0.1.1/win32yank-x64.zip" -o "$tmpdir/win32yank.zip"
    unzip -q "$tmpdir/win32yank.zip" -d "$tmpdir"
    chmod +x "$tmpdir/win32yank.exe"
    mkdir -p "$HOME/.local/bin"
    mv "$tmpdir/win32yank.exe" "$HOME/.local/bin/"
    rm -rf "$tmpdir"
    ok "win32yank installed for clipboard support"
  else
    ok "win32yank already available"
  fi
fi

# ─── TPM (Tmux Plugin Manager) ────────────────────────
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
mkdir -p "$HOME/.config/tmux/plugins"

if [ -f "$TPM_DIR/tpm" ]; then
  ok "TPM already installed"
else
  # Clean up partial clone if exists
  [ -d "$TPM_DIR" ] && rm -rf "$TPM_DIR"

  info "Installing TPM..."
  if git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"; then
    ok "TPM installed"
  else
    err "Failed to clone TPM — check your internet connection"
    err "Run manually: git clone https://github.com/tmux-plugins/tpm $TPM_DIR"
  fi
fi

# Ensure TPM scripts are executable
if [ -f "$TPM_DIR/tpm" ]; then
  chmod +x "$TPM_DIR/tpm"
  chmod +x "$TPM_DIR/bin/"* 2>/dev/null
  chmod +x "$TPM_DIR/scripts/"* 2>/dev/null
  ok "TPM scripts are executable"
else
  err "TPM not found at $TPM_DIR — plugins will not work"
  err "Run: git clone https://github.com/tmux-plugins/tpm $TPM_DIR"
fi

# ─── Tmux config ──────────────────────────────────────
TMUX_DIR="$HOME/.config/tmux"
mkdir -p "$TMUX_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$SCRIPT_DIR" != "$TMUX_DIR" ]; then
  [ -f "$SCRIPT_DIR/tmux.conf" ] && cp "$SCRIPT_DIR/tmux.conf" "$TMUX_DIR/tmux.conf" && ok "tmux.conf installed"
  [ -f "$SCRIPT_DIR/nord.omp.json" ] && cp "$SCRIPT_DIR/nord.omp.json" "$TMUX_DIR/nord.omp.json" && ok "Oh My Posh Nord theme installed"
  [ -f "$SCRIPT_DIR/catppuccin.omp.json" ] && cp "$SCRIPT_DIR/catppuccin.omp.json" "$TMUX_DIR/catppuccin.omp.json"
  [ -f "$SCRIPT_DIR/cheatsheet.txt" ] && cp "$SCRIPT_DIR/cheatsheet.txt" "$TMUX_DIR/cheatsheet.txt"
else
  ok "Config files already in place"
fi

# Symlink ~/.tmux.conf for older tmux versions (< 3.1) that don't read ~/.config/tmux/
if [ ! -e "$HOME/.tmux.conf" ]; then
  ln -sf "$TMUX_DIR/tmux.conf" "$HOME/.tmux.conf"
  ok "Symlinked ~/.tmux.conf -> ~/.config/tmux/tmux.conf"
fi

# ─── Neovim config ────────────────────────────────────
NVIM_DIR="$HOME/.config/nvim"
if [ -d "$NVIM_DIR/.git" ]; then
  remote=$(cd "$NVIM_DIR" && git remote get-url origin 2>/dev/null || echo "")
  if echo "$remote" | grep -q "irlm"; then
    info "nvim config exists, pulling..."
    (cd "$NVIM_DIR" && git pull --ff-only) && ok "nvim config updated" || warn "nvim config pull failed"
  else
    ok "nvim config exists (custom repo: $remote)"
  fi
elif [ -d "$NVIM_DIR" ]; then
  warn "nvim config exists but is not a git repo — skipping"
else
  info "Cloning nvim config..."
  git clone https://github.com/irlm/nvim.git "$NVIM_DIR"
  ok "nvim config installed"
fi

# ─── Shell plugins ────────────────────────────────────
clone_if_missing() {
  local repo=$1 dir=$2
  if [ ! -d "$dir" ]; then
    git clone --depth 1 "https://github.com/$repo.git" "$dir"
    ok "Cloned $repo"
  else
    ok "$repo already cloned"
  fi
}

if [[ "$OS" == "macos" ]]; then
  # macOS uses zsh (default shell)
  SHELL_TYPE="zsh"
  ZSH_PLUGIN_DIR="$HOME/.local/share/zsh/plugins"
  mkdir -p "$ZSH_PLUGIN_DIR"
  clone_if_missing "zsh-users/zsh-autosuggestions" "$ZSH_PLUGIN_DIR/zsh-autosuggestions"
  clone_if_missing "zsh-users/zsh-syntax-highlighting" "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting"
  clone_if_missing "zsh-users/zsh-completions" "$ZSH_PLUGIN_DIR/zsh-completions"
else
  # Linux uses bash (already default)
  SHELL_TYPE="bash"
fi

# ─── fzf keybindings ──────────────────────────────────
if [[ "$OS" == "macos" ]]; then
  if [ -f "$(brew --prefix)/opt/fzf/install" ]; then
    "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
    ok "fzf keybindings configured"
  fi
elif [ -f "$HOME/.fzf/install" ]; then
  "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-zsh --no-fish
  ok "fzf keybindings configured"
elif [ -f /usr/share/fzf/key-bindings.bash ] || [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
  ok "fzf keybindings available (sourced via shell rc)"
fi

# ─── Backup existing shell config ─────────────────────
BACKUP_DIR="$HOME/.config/shell-backup/$(date +%Y%m%d-%H%M%S)"

if [[ "$OS" == "macos" ]]; then
  # macOS: backup zsh configs + Oh My Zsh migration
  if [ -d "$HOME/.oh-my-zsh" ]; then
    warn "Oh My Zsh detected — migrating..."
    mkdir -p "$BACKUP_DIR"
    [ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$BACKUP_DIR/.zshrc" && ok "Backed up .zshrc"
    [ -f "$HOME/.zprofile" ] && cp "$HOME/.zprofile" "$BACKUP_DIR/.zprofile" && ok "Backed up .zprofile"
    [ -f "$HOME/.p10k.zsh" ] && cp "$HOME/.p10k.zsh" "$BACKUP_DIR/.p10k.zsh" && ok "Backed up .p10k.zsh"
    mv "$HOME/.oh-my-zsh" "$BACKUP_DIR/.oh-my-zsh"
    ok "Oh My Zsh moved to $BACKUP_DIR/.oh-my-zsh"
  elif [ -f "$HOME/.zshrc" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$HOME/.zshrc" "$BACKUP_DIR/.zshrc"
    warn "Backed up existing .zshrc to $BACKUP_DIR"
  fi
else
  # Linux: backup .bashrc
  if [ -f "$HOME/.bashrc" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$HOME/.bashrc" "$BACKUP_DIR/.bashrc"
    warn "Backed up existing .bashrc to $BACKUP_DIR"
  fi
fi

# ─── Write shell config ──────────────────────────────
if [[ "$SHELL_TYPE" == "zsh" ]]; then
  # ── macOS: .zshrc ──
  RCFILE="$HOME/.zshrc"
  info "Configuring .zshrc..."

  cat > "$RCFILE" << 'ZSHRC_EOF'
# ─── Path ────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

# ─── Homebrew (macOS) ───────────────────────────────────
if [ -d /opt/homebrew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ─── Oh My Posh prompt ──────────────────────────────────
if command -v oh-my-posh &>/dev/null; then
  eval "$(oh-my-posh init zsh --config ~/.config/tmux/nord.omp.json)"
fi

# ─── Zsh options ─────────────────────────────────────────
setopt AUTO_CD HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS SHARE_HISTORY CORRECT
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history

# ─── Completion ──────────────────────────────────────────
autoload -Uz compinit
compinit -C
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# ─── Plugins ─────────────────────────────────────────────
ZSH_PLUGIN_DIR="$HOME/.local/share/zsh/plugins"
[ -f "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && source "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
[ -f "$ZSH_PLUGIN_DIR/zsh-completions/zsh-completions.plugin.zsh" ] && source "$ZSH_PLUGIN_DIR/zsh-completions/zsh-completions.plugin.zsh"
[ -f "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] && source "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# ─── fzf ─────────────────────────────────────────────────
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_OPTS="--color=fg:#d8dee9,bg:#2e3440,hl:#88c0d0 --color=fg+:#eceff4,bg+:#434c5e,hl+:#5e81ac --color=info:#ebcb8b,prompt:#81a1c1,pointer:#bf616a --color=marker:#a3be8c,spinner:#b48ead,header:#88c0d0"

# ─── Modern CLI aliases ─────────────────────────────────
command -v eza    &>/dev/null && alias ls='eza --icons' && alias ll='eza -la --icons --git' && alias tree='eza --tree --icons'
command -v bat    &>/dev/null && alias cat='bat --style=plain'
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# ─── Useful aliases ──────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias g='git'
alias gs='git status'
alias gl='git log --oneline --graph --decorate -20'
alias gp='git push'
alias gpl='git pull'
alias lg='lazygit'
alias t='tmux'
alias ta='tmux attach || tmux new'
command -v tlrc &>/dev/null && alias help='tlrc'

# ─── Fastfetch on new shell (only interactive, non-tmux) ─
if [[ $- == *i* ]] && [ -z "$TMUX" ] && command -v fastfetch &>/dev/null; then
  fastfetch -l small --structure Title:OS:Host:Kernel:Shell:Terminal:CPU:Memory
fi

# ─── Source extras ───────────────────────────────────────
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
ZSHRC_EOF

else
  # ── Linux: .bashrc ──
  RCFILE="$HOME/.bashrc"
  info "Configuring .bashrc..."

  cat > "$RCFILE" << 'BASHRC_EOF'
# ─── Path ────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

# ─── Oh My Posh prompt ──────────────────────────────────
if command -v oh-my-posh &>/dev/null; then
  eval "$(oh-my-posh init bash --config ~/.config/tmux/nord.omp.json)"
fi

# ─── History ─────────────────────────────────────────────
HISTSIZE=50000
HISTFILESIZE=50000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

# ─── Shell options ───────────────────────────────────────
shopt -s autocd 2>/dev/null         # cd by typing directory name
shopt -s cdspell                    # fix minor cd typos
shopt -s checkwinsize               # update LINES/COLUMNS after resize
shopt -s globstar 2>/dev/null       # ** recursive glob

# ─── fzf ─────────────────────────────────────────────────
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
[ -f /usr/share/fzf/key-bindings.bash ] && source /usr/share/fzf/key-bindings.bash
[ -f /usr/share/fzf/completion.bash ] && source /usr/share/fzf/completion.bash
[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && source /usr/share/doc/fzf/examples/key-bindings.bash
[ -f /usr/share/doc/fzf/examples/completion.bash ] && source /usr/share/doc/fzf/examples/completion.bash
export FZF_DEFAULT_OPTS="--color=fg:#d8dee9,bg:#2e3440,hl:#88c0d0 --color=fg+:#eceff4,bg+:#434c5e,hl+:#5e81ac --color=info:#ebcb8b,prompt:#81a1c1,pointer:#bf616a --color=marker:#a3be8c,spinner:#b48ead,header:#88c0d0"

# ─── Modern CLI aliases ─────────────────────────────────
command -v eza    &>/dev/null && alias ls='eza --icons' && alias ll='eza -la --icons --git' && alias tree='eza --tree --icons'
command -v bat    &>/dev/null && alias cat='bat --style=plain'
command -v zoxide &>/dev/null && eval "$(zoxide init bash)"

# ─── Useful aliases ──────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias g='git'
alias gs='git status'
alias gl='git log --oneline --graph --decorate -20'
alias gp='git push'
alias gpl='git pull'
alias lg='lazygit'
alias t='tmux'
alias ta='tmux attach || tmux new'
command -v tlrc &>/dev/null && alias help='tlrc'

# ─── WSL browser ─────────────────────────────────────────
if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
  command -v wslview &>/dev/null && export BROWSER="wslview"
fi

# ─── Fastfetch on new shell (only interactive, non-tmux) ─
if [[ $- == *i* ]] && [ -z "$TMUX" ] && command -v fastfetch &>/dev/null; then
  fastfetch -l small --structure Title:OS:Host:Kernel:Shell:Terminal:CPU:Memory
fi

# ─── Source extras ───────────────────────────────────────
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
BASHRC_EOF

fi

ok "$RCFILE configured"

# ─── Install tmux plugins ─────────────────────────────
info "Installing tmux plugins via TPM..."
if [ -f "$TPM_DIR/bin/install_plugins" ]; then
  # TPM install_plugins needs a running tmux server
  # Start a detached server if none exists, install plugins, then kill it
  if ! tmux list-sessions &>/dev/null; then
    info "Starting temporary tmux server for plugin install..."
    tmux new-session -d -s _tpm_install 2>/dev/null
    "$TPM_DIR/bin/install_plugins" 2>/dev/null && ok "Plugins installed" || warn "Plugin install failed — press C-a I inside tmux"
    tmux kill-session -t _tpm_install 2>/dev/null
  else
    "$TPM_DIR/bin/install_plugins" 2>/dev/null && ok "Plugins installed" || warn "Plugin install failed — press C-a I inside tmux"
  fi
else
  warn "TPM not found — start tmux and press C-a I to install plugins"
fi

# ─── Done ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Platform: $OS ${DISTRO:+($DISTRO)} ${IS_WSL:+(WSL)}"
echo ""
echo "  Next steps:"
echo "  1. Set your terminal font to 'JetBrains Mono Nerd Font'"
if $IS_WSL; then
  echo "     (Install the font on Windows, not inside WSL)"
fi
echo "  2. Open a new terminal or run: source $RCFILE"
echo "  3. Start tmux: tmux"
echo "  4. Install tmux plugins: C-a I"
echo ""
echo "  What you got:"
echo "    - Oh My Posh prompt with Nord theme + git status"
echo "    - tmux with C-a prefix, popups, vim bindings"
echo "    - neovim with LazyVim (LSPs for Rust, Go, Python, TS, Java, Scala, C/C++, SQL)"
echo "    - Docker + lazydocker"
echo "    - fzf (C-r history, C-t files, Alt-c directories)"
echo "    - lazygit, btop, gh popups inside tmux"
echo "    - fastfetch greeting on new terminal"
echo "    - eza/bat/zoxide replacing ls/cat/cd"
echo "    - tlrc (quick man pages), jq (JSON)"
if [[ "$SHELL_TYPE" == "zsh" ]]; then
  echo "    - zsh autosuggestions + syntax highlighting"
fi
if $IS_WSL; then
  echo "    - win32yank for WSL clipboard integration"
fi
echo ""
