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

    # Install zsh if missing
    if ! command -v zsh &>/dev/null; then
      info "Installing zsh..."
      pkg_install zsh
      ok "zsh installed"
    else
      ok "zsh already installed"
    fi

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
      tmux fzf lazygit btop fastfetch gh
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
    case "$PKG_MGR" in
      apt)
        # Try repo first, fallback to GitHub
        pkg_install fastfetch 2>/dev/null || \
          install_from_github "fastfetch-cli/fastfetch" "fastfetch" "linux-$(gh_arch amd64 aarch64).*\\.deb"
        ;;
      dnf)
        pkg_install fastfetch 2>/dev/null || \
          install_from_github "fastfetch-cli/fastfetch" "fastfetch" "linux-$(gh_arch amd64 aarch64).*\\.rpm"
        ;;
      zypper)
        pkg_install fastfetch 2>/dev/null || \
          install_from_github "fastfetch-cli/fastfetch" "fastfetch" "linux-$(gh_arch amd64 aarch64).*\\.rpm"
        ;;
    esac
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
          install_from_github "eza-community/eza" "eza" "linux-$(gh_arch x86_64 aarch64)-musl.*\\.tar\\.gz"
        ;;
      zypper)
        pkg_install eza 2>/dev/null || \
          install_from_github "eza-community/eza" "eza" "linux-$(gh_arch x86_64 aarch64)-musl.*\\.tar\\.gz"
        ;;
    esac
  fi

  # tlrc (Rust tldr client — install from GitHub release)
  if ! command -v tlrc &>/dev/null; then
    install_from_github "tldr-pages/tlrc" "tlrc" "$(gh_arch x86_64 aarch64).*linux.*musl.*\\.tar\\.gz"
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
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
  info "Installing TPM..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
  ok "TPM installed"
else
  ok "TPM already installed"
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

# ─── Zsh plugins (standalone, no framework) ───────────
ZSH_PLUGIN_DIR="$HOME/.local/share/zsh/plugins"
mkdir -p "$ZSH_PLUGIN_DIR"

clone_if_missing() {
  local repo=$1 dir=$2
  if [ ! -d "$dir" ]; then
    git clone --depth 1 "https://github.com/$repo.git" "$dir"
    ok "Cloned $repo"
  else
    ok "$repo already cloned"
  fi
}

clone_if_missing "zsh-users/zsh-autosuggestions" "$ZSH_PLUGIN_DIR/zsh-autosuggestions"
clone_if_missing "zsh-users/zsh-syntax-highlighting" "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting"
clone_if_missing "zsh-users/zsh-completions" "$ZSH_PLUGIN_DIR/zsh-completions"

# ─── fzf keybindings ──────────────────────────────────
if [[ "$OS" == "macos" ]]; then
  if [ -f "$(brew --prefix)/opt/fzf/install" ]; then
    "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
    ok "fzf keybindings configured"
  fi
elif [ -f "$HOME/.fzf/install" ]; then
  "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
  ok "fzf keybindings configured"
elif [ -f /usr/share/fzf/key-bindings.zsh ] || [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
  ok "fzf keybindings available (sourced via .zshrc)"
fi

# ─── Migrate from Oh My Zsh (if present) ──────────────
BACKUP_DIR="$HOME/.config/shell-backup/$(date +%Y%m%d-%H%M%S)"
if [ -d "$HOME/.oh-my-zsh" ]; then
  warn "Oh My Zsh detected — migrating..."
  mkdir -p "$BACKUP_DIR"
  [ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$BACKUP_DIR/.zshrc" && ok "Backed up .zshrc"
  [ -f "$HOME/.zprofile" ] && cp "$HOME/.zprofile" "$BACKUP_DIR/.zprofile" && ok "Backed up .zprofile"
  [ -f "$HOME/.zshenv" ] && cp "$HOME/.zshenv" "$BACKUP_DIR/.zshenv" && ok "Backed up .zshenv"
  [ -f "$HOME/.p10k.zsh" ] && cp "$HOME/.p10k.zsh" "$BACKUP_DIR/.p10k.zsh" && ok "Backed up .p10k.zsh"
  mv "$HOME/.oh-my-zsh" "$BACKUP_DIR/.oh-my-zsh"
  ok "Oh My Zsh moved to $BACKUP_DIR/.oh-my-zsh"
  warn "To restore: cp -r $BACKUP_DIR/.oh-my-zsh ~/  && cp $BACKUP_DIR/.zshrc ~/"
else
  # Backup any existing zsh config even without OMZ
  if [ -f "$HOME/.zshrc" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$HOME/.zshrc" "$BACKUP_DIR/.zshrc"
    [ -f "$HOME/.zprofile" ] && cp "$HOME/.zprofile" "$BACKUP_DIR/.zprofile"
    [ -f "$HOME/.zshenv" ] && cp "$HOME/.zshenv" "$BACKUP_DIR/.zshenv"
    warn "Backed up existing shell configs to $BACKUP_DIR"
  fi
fi

# ─── Write .zshrc ─────────────────────────────────────
ZSHRC="$HOME/.zshrc"
info "Configuring .zshrc..."

cat > "$ZSHRC" << 'ZSHRC_EOF'
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
setopt AUTO_CD                # cd by typing directory name
setopt HIST_IGNORE_ALL_DUPS   # no duplicate history entries
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY          # share history across sessions
setopt CORRECT                # spelling correction
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history

# ─── Completion ──────────────────────────────────────────
autoload -Uz compinit
compinit -C
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'    # case-insensitive
zstyle ':completion:*' menu select                       # arrow-key menu
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"  # colored completions

# ─── Plugins ─────────────────────────────────────────────
ZSH_PLUGIN_DIR="$HOME/.local/share/zsh/plugins"
[ -f "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && source "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
[ -f "$ZSH_PLUGIN_DIR/zsh-completions/zsh-completions.plugin.zsh" ] && source "$ZSH_PLUGIN_DIR/zsh-completions/zsh-completions.plugin.zsh"
# syntax-highlighting must be sourced last
[ -f "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] && source "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# ─── fzf ─────────────────────────────────────────────────
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# Linux: fzf from package manager
[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh
[ -f /usr/share/fzf/completion.zsh ] && source /usr/share/fzf/completion.zsh
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh
export FZF_DEFAULT_OPTS="--color=fg:#d8dee9,bg:#2e3440,hl:#88c0d0 --color=fg+:#eceff4,bg+:#434c5e,hl+:#5e81ac --color=info:#ebcb8b,prompt:#81a1c1,pointer:#bf616a --color=marker:#a3be8c,spinner:#b48ead,header:#88c0d0"

# ─── Modern CLI aliases ─────────────────────────────────
command -v eza   &>/dev/null && alias ls='eza --icons'   && alias ll='eza -la --icons --git' && alias tree='eza --tree --icons'
command -v bat   &>/dev/null && alias cat='bat --style=plain'
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)" # use 'z' instead of 'cd'

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

# ─── Source extras (cargo, coursier, etc.) ───────────────
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
ZSHRC_EOF

ok ".zshrc configured"

# ─── Set default shell to zsh (Linux only) ────────────
if [[ "$OS" == "linux" ]]; then
  ZSH_PATH="$(command -v zsh)"
  if [ "$SHELL" != "$ZSH_PATH" ]; then
    info "Setting zsh as default shell..."
    if chsh -s "$ZSH_PATH" 2>/dev/null; then
      ok "Default shell changed to zsh (takes effect on next login)"
    else
      warn "Could not change shell — run manually: chsh -s $ZSH_PATH"
    fi
  else
    ok "zsh is already the default shell"
  fi
fi

# ─── Install tmux plugins ─────────────────────────────
info "Installing tmux plugins via TPM..."
"$TPM_DIR/bin/install_plugins" 2>/dev/null || warn "Start tmux and press C-a I to install plugins"

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
if [[ "$OS" == "linux" ]] && [ "$SHELL" != "$(command -v zsh)" ]; then
  echo "  2. Log out and back in (to activate zsh as default shell)"
  echo "  3. Start tmux: tmux"
  echo "  4. Install tmux plugins: C-a I"
else
  echo "  2. Open a new terminal or run: source ~/.zshrc"
  echo "  3. Start tmux: tmux"
  echo "  4. Install tmux plugins: C-a I"
fi
echo ""
echo "  What you got:"
echo "    - Oh My Posh prompt with Nord theme + git status"
echo "    - tmux with C-a prefix, popups, vim bindings"
echo "    - fzf (C-r history, C-t files, Alt-c directories)"
echo "    - lazygit, btop, gh popups inside tmux"
echo "    - fastfetch greeting on new terminal"
echo "    - eza/bat/zoxide replacing ls/cat/cd"
echo "    - tlrc (quick man pages), jq (JSON)"
echo "    - zsh autosuggestions + syntax highlighting"
if $IS_WSL; then
  echo "    - win32yank for WSL clipboard integration"
fi
echo ""
