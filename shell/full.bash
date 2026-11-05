# ─── Path ────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

# Homebrew's openjdk is keg-only, so without this `java` resolves to the
# macOS stub that has no runtime behind it.
for _jdk in /opt/homebrew/opt/openjdk/bin /usr/local/opt/openjdk/bin; do
  [ -d "$_jdk" ] && export PATH="$_jdk:$PATH" && break
done
unset _jdk

# Coursier installs metals and scalafmt here, outside any default PATH.
for _cs_bin in "$HOME/Library/Application Support/Coursier/bin" "$HOME/.local/share/coursier/bin"; do
  [ -d "$_cs_bin" ] && export PATH="$_cs_bin:$PATH" && break
done
unset _cs_bin

# ─── Oh My Posh prompt ──────────────────────────────────
_tmux_prompt="${TMUX_THEME_DIR:-$HOME/.config/tmux-user}/prompt.omp.json"
[ -f "$_tmux_prompt" ] || _tmux_prompt="$HOME/.config/tmux/nord.omp.json"
if command -v oh-my-posh &>/dev/null; then
  eval "$(oh-my-posh init bash --config "$_tmux_prompt")"
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
alias lg='~/.config/tmux/scripts/lazygit.sh'
alias t='tmux'
alias ta='tmux attach || tmux new'
alias dotup='~/.config/tmux/update.sh'          # update repos, plugins, tools
alias dotcheck='~/.config/tmux/update.sh --check'  # report only, change nothing
command -v tlrc &>/dev/null && alias help='tlrc'

# ─── WSL browser ─────────────────────────────────────────
if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
  command -v wslview &>/dev/null && export BROWSER="wslview"
fi

# ─── Fastfetch on new shell (only interactive, non-tmux) ─
# Once per shell, and not while the rc file still carries the older inline
# copy of this block (installs before Nov 2026 pasted it into the rc file;
# doctor.sh says which lines to remove).
if [[ $- == *i* ]] && [ -z "$TMUX" ] && [ -z "${__WB_BANNER_SHOWN:-}" ] && command -v fastfetch &>/dev/null \
   && ! grep -qs 'fastfetch -l small' "$HOME/.bashrc"; then
  __WB_BANNER_SHOWN=1
  fastfetch -l small --structure Title:OS:Host:Kernel:Shell:Terminal:CPU:Memory
fi

# ─── Editor ─────────────────────────────────────────────
export EDITOR=nvim
export VISUAL=nvim
alias svim="sudo -E nvim"  # sudo nvim with your config

# ─── Source extras ───────────────────────────────────────
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

[ ! -f "$HOME/.config/tmux/shell/theme-env.sh" ] || . "$HOME/.config/tmux/shell/theme-env.sh"
unset _tmux_prompt
