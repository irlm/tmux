#!/usr/bin/env zsh
# ─── Lightweight server prompt (zsh) ─────────────────────
# Pure zsh — no external binaries, no oh-my-posh overhead
# Source this in .zshrc: [ -f ~/.config/tmux/scripts/prompt.zsh ] && . ~/.config/tmux/scripts/prompt.zsh

autoload -Uz vcs_info
__tmux_precmd() {
  vcs_info
  # At a bare ssh shell, put the terminal title back to the hostname. A tmux
  # that exited uncleanly leaves its "tmux-remote:" title behind, and the tmux
  # you connected from would take the next full-screen program for it.
  [[ -n $SSH_CONNECTION && -z $TMUX ]] && print -Pn '\e]2;%m\e\\'
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd __tmux_precmd
zstyle ':vcs_info:git:*' formats ' %b'

setopt PROMPT_SUBST

# user@host (green normal, red root), path, git branch, exit code
PROMPT='%(?..'$'\e[31m''[%?]'$'\e[0m'' )%B%F{green}%n%b%f%F{8}@%f%F{cyan}%m%f %B%F{blue}%~%b%f%F{yellow}${vcs_info_msg_0_}%f %F{8}$%f '
