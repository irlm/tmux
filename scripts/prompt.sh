#!/usr/bin/env bash
# ─── Lightweight server prompt ────────────────────────────
# Pure bash — no external binaries, no oh-my-posh overhead
# Source this in .bashrc: [ -f ~/.config/tmux/scripts/prompt.sh ] && . ~/.config/tmux/scripts/prompt.sh

__git_branch() {
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    [ -n "$branch" ] && printf ' %s' "$branch"
}

__prompt_cmd() {
    local exit_code=$?
    local reset='\[\e[0m\]'
    local bold='\[\e[1m\]'
    local dim='\[\e[2m\]'
    local red='\[\e[31m\]'
    local green='\[\e[32m\]'
    local yellow='\[\e[33m\]'
    local blue='\[\e[34m\]'
    local cyan='\[\e[36m\]'

    # user@host (green for normal, red for root)
    local user_color="$green"
    [ "$(id -u)" -eq 0 ] && user_color="$red"

    PS1=""
    # Exit code (only if non-zero)
    [ "$exit_code" -ne 0 ] && PS1+="${red}[${exit_code}]${reset} "
    # user@host
    PS1+="${user_color}${bold}\u${reset}${dim}@${reset}${cyan}\h${reset}"
    # path
    PS1+=" ${blue}${bold}\w${reset}"
    # git branch
    PS1+="${yellow}\$(__git_branch)${reset}"
    # prompt char
    PS1+=" ${dim}\$${reset} "
}

PROMPT_COMMAND=__prompt_cmd
