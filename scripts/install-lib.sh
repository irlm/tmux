#!/usr/bin/env bash
# Shared installer behavior. Safe to source without installing anything.
install_target_shell() {
    local login_shell=${SHELL:-/bin/bash}
    case "${TMUX_TARGET_SHELL:-${login_shell##*/}}" in
        bash|zsh) printf '%s\n' "${TMUX_TARGET_SHELL:-${login_shell##*/}}" ;;
        *) echo 'Supported target shells: bash, zsh (set TMUX_TARGET_SHELL).' >&2; return 1 ;;
    esac
}

shell_rc_file() {
    local target
    target=$(install_target_shell) || return 1
    if [ "$target" = zsh ]; then
        printf '%s\n' "$HOME/.zshrc"
    else
        # Bash interactive panes read .bashrc, even when a login profile exists.
        printf '%s\n' "$HOME/.bashrc"
    fi
}

managed_remote() {
    local remote=${1%.git} name=${2%.git}
    case "$remote" in
        "https://github.com/irlm/$name"|"git@github.com:irlm/$name"|"ssh://git@github.com/irlm/$name") return 0 ;;
        *) return 1 ;;
    esac
}

clone_config() {
    local name=${1%.git} dest=$2 remote stage backup
    if [ -d "$dest/.git" ] || [ -f "$dest/.git" ]; then
        remote=$(git -C "$dest" remote get-url origin 2>/dev/null) || remote=""
        if managed_remote "$remote" "$name"; then
            git -C "$dest" pull --ff-only
            return
        fi
    fi
    mkdir -p "$(dirname "$dest")"
    stage=$(mktemp -d "${dest}.stage.XXXXXX") || return 1
    if ! git clone "https://github.com/irlm/$name.git" "$stage"; then
        rm -rf -- "$stage"
        return 1
    fi
    backup=""
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        backup="${dest}.backup.$(date +%Y%m%d-%H%M%S).${stage##*.}"
        if ! mv -- "$dest" "$backup"; then rm -rf -- "$stage"; return 1; fi
        printf 'Previous config saved to %s\n' "$backup"
    fi
    if ! mv -- "$stage" "$dest"; then
        [ -z "$backup" ] || mv -- "$backup" "$dest"
        return 1
    fi
}

# Emit integration for the chosen shell. User rc files source this managed file.
write_shell_integration() {
    local target=$1 profile=${2:-desktop} dest=$3
    {
        printf '# Managed tmux integration; keep personal settings in your shell rc.\n'
        printf '[ "${__TMUX_SHELL_ENV_LOADED:-}" != "%s" ] || return 0\n__TMUX_SHELL_ENV_LOADED=%s\n' "$profile" "$profile"
        printf 'export PATH="$HOME/.local/bin:$PATH"\n'
        cat <<'PATH_BLOCK'
for _tool_path in /opt/homebrew/opt/openjdk/bin /usr/local/opt/openjdk/bin "$HOME/Library/Application Support/Coursier/bin" "$HOME/.local/share/coursier/bin"; do
    if [ -d "$_tool_path" ]; then
        case ":$PATH:" in *":$_tool_path:"*) ;; *) PATH="$_tool_path:$PATH" ;; esac
    fi
done
unset _tool_path
PATH_BLOCK
        if [ "$profile" = full ]; then
            printf '[ ! -f "$HOME/.config/tmux/shell/full.%s" ] || . "$HOME/.config/tmux/shell/full.%s"\n' "$target" "$target"
        elif [ "$profile" = server ]; then
            if [ "$target" = zsh ]; then
                printf '[ ! -f "$HOME/.config/tmux/scripts/prompt.zsh" ] || . "$HOME/.config/tmux/scripts/prompt.zsh"\n'
            else
                printf '[ ! -f "$HOME/.config/tmux/scripts/prompt.sh" ] || . "$HOME/.config/tmux/scripts/prompt.sh"\n'
            fi
        else
            printf '_tmux_prompt="${TMUX_THEME_DIR:-$HOME/.config/tmux-user}/prompt.omp.json"\n'
            printf '[ -f "$_tmux_prompt" ] || _tmux_prompt="$HOME/.config/tmux/nord.omp.json"\n'
            printf 'command -v oh-my-posh >/dev/null 2>&1 && eval "$(oh-my-posh init %s --config "$_tmux_prompt")"\nunset _tmux_prompt\n' "$target"
        fi
        if [ "$profile" != full ]; then
            printf 'command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init %s)"\n' "$target"
        fi
        printf 'export EDITOR="${EDITOR:-nvim}"\nexport VISUAL="${VISUAL:-$EDITOR}"\n'
        printf "alias dotup='~/.config/tmux/update.sh'\nalias dotcheck='~/.config/tmux/update.sh --check'\n"
        printf '[ ! -f "$HOME/.config/tmux/shell/theme-env.sh" ] || . "$HOME/.config/tmux/shell/theme-env.sh"\n'
        printf 'true\n'
    } > "$dest"
}

append_shell_include() {
    local rc=$1 target=$2 backup
    if ! grep -F 'tmux-user/shell.' "$rc" >/dev/null 2>&1; then
        if [ -f "$rc" ]; then
            backup=$(mktemp "${rc}.backup.XXXXXX")
            cp -p "$rc" "$backup"
        fi
        printf '\n# tmux environment\n[ ! -f "$HOME/.config/tmux-user/shell.%s" ] || . "$HOME/.config/tmux-user/shell.%s"\n' "$target" "$target" >> "$rc"
    fi
}

install_shell_integration() {
    local profile=${1:-desktop} target rc managed login candidate
    target=$(install_target_shell) || return 1
    rc=$(shell_rc_file) || return 1
    mkdir -p "$HOME/.config/tmux-user"
    managed="$HOME/.config/tmux-user/shell.$target"
    write_shell_integration "$target" "$profile" "$managed"
    append_shell_include "$rc" "$target"
    if [ "$target" = bash ]; then
        # Login shells read only the first of these files; don't mask .profile.
        login="$HOME/.bash_profile"
        for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
            if [ -f "$candidate" ]; then login="$candidate"; break; fi
        done
        append_shell_include "$login" bash
    fi
    printf 'Shell integration: %s (%s)\n' "$rc" "$target"
}

install_brew_tools() {
    local profile=$1 assets=$2 command formula _ scope
    while IFS=$'\t' read -r command formula _ scope; do
        [ "$command" != command ] || continue
        [ "$profile" != server ] || [ "$scope" = all ] || continue
        [ "$formula" != - ] || continue
        command -v "$command" >/dev/null 2>&1 || brew install "$formula"
    done < "$assets/tools.tsv"
}

install_tmux_plugins() {
    local dir=$1 tpm="$1/plugins/tpm" action
    if [ ! -x "$tpm/tpm" ]; then
        mkdir -p "$dir/plugins"
        [ ! -e "$tpm" ] || mv -- "$tpm" "$tpm.backup.$(date +%Y%m%d-%H%M%S)"
        git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm" || return 1
    fi
    if ! tmux list-sessions >/dev/null 2>&1; then
        printf 'TPM is ready. Start tmux and press C-a I to install plugins.\n'
        return 0
    fi
    tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$dir/plugins"
    for action in install_plugins update_plugins clean_plugins; do
        if [ "$action" = update_plugins ]; then "$tpm/bin/$action" all || return 1;
        else "$tpm/bin/$action" || return 1; fi
    done
}

check_install_tools() {
    local profile=$1 assets=$2 command _ scope missing=""
    while IFS=$'\t' read -r command _ _ scope; do
        [ "$command" != command ] || continue
        [ "$profile" != server ] || [ "$scope" = all ] || continue
        command -v "$command" >/dev/null 2>&1 || missing="$missing $command"
    done < "$assets/tools.tsv"
    if [ -n "$missing" ]; then
        printf 'Install incomplete. Required tools missing:%s\nRun ~/.config/tmux/update.sh --fix after resolving the errors above.\n' "$missing" >&2
        return 1
    fi
}

# Herdr: render this repo's config and plugin for it and wire the agent
# integrations. Installs Herdr itself only when asked (install.sh --herdr).
install_herdr_workbench() {
    local assets=$1 want=${2:-0} agent
    if ! command -v herdr >/dev/null 2>&1; then
        [ "$want" = 1 ] || return 0
        echo "Installing Herdr (https://herdr.dev)..."
        if ! curl -fsSL https://herdr.dev/install.sh | sh; then
            echo '  Herdr install failed; see https://herdr.dev/tui/docs/install/' >&2
            return 1
        fi
        [ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
        command -v herdr >/dev/null 2>&1 || { echo '  herdr is not on PATH yet; open a new shell and rerun install.sh --herdr' >&2; return 1; }
    fi
    bash "$assets/scripts/herdr-config.sh" || return 1
    for agent in claude codex; do
        command -v "$agent" >/dev/null 2>&1 || continue
        herdr integration install "$agent" >/dev/null 2>&1 && printf 'Herdr integration: %s\n' "$agent"
    done
}
