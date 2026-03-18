#!/bin/bash
# ─── Tmux + Shell Bootstrap ──────────────────────────────
# Run on a fresh macOS machine:  curl -sL <raw-url> | bash
# Or locally:                    bash ~/.config/tmux/setup.sh
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ─── Homebrew ─────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv zsh)"
  ok "Homebrew installed"
else
  ok "Homebrew already installed"
fi

# ─── Core tools ──────────────────────────────────────────
BREW_PACKAGES=(
  tmux
  oh-my-posh
  fzf
  lazygit
  btop
  fastfetch
  gh
  ripgrep
  fd
  bat
  eza
  zoxide
  tlrc
  jq
)

info "Installing packages..."
for pkg in "${BREW_PACKAGES[@]}"; do
  if brew list "$pkg" &>/dev/null; then
    ok "$pkg already installed"
  else
    info "Installing $pkg..."
    brew install "$pkg"
    ok "$pkg installed"
  fi
done

# ─── Nerd Font (needed for Oh My Posh glyphs) ────────────
if ! brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
  info "Installing JetBrains Mono Nerd Font..."
  brew install --cask font-jetbrains-mono-nerd-font
  ok "Nerd Font installed — set it as your terminal font"
else
  ok "Nerd Font already installed"
fi

# ─── TPM (Tmux Plugin Manager) ───────────────────────────
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
  info "Installing TPM..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
  ok "TPM installed"
else
  ok "TPM already installed"
fi

# ─── Tmux config ─────────────────────────────────────────
TMUX_DIR="$HOME/.config/tmux"
mkdir -p "$TMUX_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$SCRIPT_DIR" != "$TMUX_DIR" ]; then
  [ -f "$SCRIPT_DIR/tmux.conf" ] && cp "$SCRIPT_DIR/tmux.conf" "$TMUX_DIR/tmux.conf" && ok "tmux.conf installed"
  [ -f "$SCRIPT_DIR/nord.omp.json" ] && cp "$SCRIPT_DIR/nord.omp.json" "$TMUX_DIR/nord.omp.json" && ok "Oh My Posh Nord theme installed"
else
  ok "Config files already in place"
fi

# ─── Zsh plugins (standalone, no framework) ──────────────
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

# ─── fzf keybindings ─────────────────────────────────────
if [ -f "$(brew --prefix)/opt/fzf/install" ]; then
  "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
  ok "fzf keybindings configured"
fi

# ─── Migrate from Oh My Zsh (if present) ────────────────
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

# ─── Write .zshrc ────────────────────────────────────────
ZSHRC="$HOME/.zshrc"
info "Configuring .zshrc..."

cat > "$ZSHRC" << 'ZSHRC_EOF'
# ─── Path ────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

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

# ─── Fastfetch on new shell (only interactive, non-tmux) ─
if [[ $- == *i* ]] && [ -z "$TMUX" ] && command -v fastfetch &>/dev/null; then
  fastfetch -l small --structure Title:OS:Host:Kernel:Shell:Terminal:CPU:Memory
fi

# ─── Source extras (cargo, coursier, etc.) ───────────────
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
ZSHRC_EOF

ok ".zshrc configured"

# ─── Install tmux plugins ────────────────────────────────
info "Installing tmux plugins via TPM..."
"$TPM_DIR/bin/install_plugins" 2>/dev/null || warn "Start tmux and press C-a I to install plugins"

# ─── Done ─────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Next steps:"
echo "  1. Set your terminal font to 'JetBrains Mono Nerd Font'"
echo "  2. Open a new terminal or run: source ~/.zshrc"
echo "  3. Start tmux: tmux"
echo "  4. Install tmux plugins: C-a I"
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
echo ""
