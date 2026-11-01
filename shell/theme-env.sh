#!/bin/sh
# Shared by Bash and Zsh. Theme changes take effect in newly opened shells.
_tmux_theme_dir="${TMUX_THEME_DIR:-$HOME/.config/tmux-user}"
if [ -r "$_tmux_theme_dir/prompt.omp.json" ] && [ -n "${POSH_CONFIG:-}" ]; then
    export POSH_CONFIG="$_tmux_theme_dir/prompt.omp.json"
fi
if [ -r "$_tmux_theme_dir/lazygit.yml" ]; then
    case ",${LG_CONFIG_FILE:-}," in
        *",$_tmux_theme_dir/lazygit.yml,"*) ;;
        *)
            if [ -z "${LG_CONFIG_FILE:-}" ] && command -v lazygit >/dev/null 2>&1; then
                _tmux_lg_dir=$(lazygit --print-config-dir 2>/dev/null)
                [ ! -f "$_tmux_lg_dir/config.yml" ] || LG_CONFIG_FILE="$_tmux_lg_dir/config.yml"
            fi
            export LG_CONFIG_FILE="${LG_CONFIG_FILE:+$LG_CONFIG_FILE,}$_tmux_theme_dir/lazygit.yml"
            ;;
    esac
fi
if [ -r "$_tmux_theme_dir/fzf.opts" ]; then
    IFS= read -r _tmux_fzf_colors < "$_tmux_theme_dir/fzf.opts"
    case " ${FZF_DEFAULT_OPTS:-} " in
        *" $_tmux_fzf_colors "*) ;;
        *) export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS }$_tmux_fzf_colors" ;;
    esac
fi
unset _tmux_theme_dir _tmux_lg_dir _tmux_fzf_colors
