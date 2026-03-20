#!/usr/bin/env zsh
# ─── Lightweight server prompt (zsh) ─────────────────────
# Pure zsh — no external binaries, no oh-my-posh overhead
# Source this in .zshrc: [ -f ~/.config/tmux/scripts/prompt.zsh ] && . ~/.config/tmux/scripts/prompt.zsh

autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' %b'

setopt PROMPT_SUBST

# user@host (green normal, red root), path, git branch, exit code
PROMPT='%(?..'$'\e[31m''[%?]'$'\e[0m'' )%B%F{green}%n%b%f%F{8}@%f%F{cyan}%m%f %B%F{blue}%~%b%f%F{yellow}${vcs_info_msg_0_}%f %F{8}$%f '
