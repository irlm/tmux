#!/usr/bin/env bash
# Run a tool inside a tmux popup, or say why it cannot.
#
#   popup.sh <command> [args...]           run it
#   popup.sh --any <a> <b> ... -- [args]   run the first of a, b, ... that exists
#   popup.sh --need <tool> -- <shell cmd>  run a shell snippet that relies on <tool>
#   popup.sh --gh-ext <name> -- <cmd>      like --need, for a gh extension
#
# A popup whose command is missing closes the instant it opens, which reads
# as "the key does nothing". This keeps the popup up with the reason and the
# way to fix it instead. Also tries a login shell's PATH before giving up,
# for tools installed after the tmux server started.

# Tools installed by these dotfiles, so "how to fix" can be specific.
MANAGED="tmux nvim git fzf zoxide bat btop htop fastfetch lazygit lazydocker gh oh-my-posh rg fd jq w3m tldr curl"

have() { command -v "$1" >/dev/null 2>&1; }

retry_with_login_path() {
    local login_path
    login_path=$("${SHELL:-sh}" -lc 'printf %s "$PATH"' 2>/dev/null)
    [ -n "$login_path" ] && export PATH="$login_path:$PATH"
}

fail() {  # $1 = what is missing, $2 = how to fix
    echo ""
    echo "  $1 on $(hostname -s 2>/dev/null || hostname)."
    echo ""
    [ -n "${2:-}" ] && { echo "  $2"; echo ""; }
    read -rp "  Press Enter to close..." _
    exit 127
}

fix_hint() {  # for a plain tool name
    case " $MANAGED " in
        *" $1 "*) echo "Install it with:  ~/.config/tmux/update.sh --fix" ;;
        *)        echo "" ;;
    esac
}

mode="run"
case "${1:-}" in
    --any|--need|--gh-ext) mode="${1#--}"; shift ;;
esac

case "$mode" in
    run)
        cmd="${1:-}"; [ -z "$cmd" ] && exit 1
        have "$cmd" || retry_with_login_path
        have "$cmd" && exec "$@"
        fail "'$cmd' is not installed" "$(fix_hint "$cmd")"
        ;;
    any)
        candidates=()
        while [ $# -gt 0 ] && [ "$1" != "--" ]; do candidates+=("$1"); shift; done
        [ "${1:-}" = "--" ] && shift
        for c in "${candidates[@]}"; do have "$c" && exec "$c" "$@"; done
        retry_with_login_path
        for c in "${candidates[@]}"; do have "$c" && exec "$c" "$@"; done
        fail "none of: ${candidates[*]} is installed" "$(fix_hint "${candidates[0]}")"
        ;;
    need)
        tool="${1:-}"; shift; [ "${1:-}" = "--" ] && shift
        have "$tool" || retry_with_login_path
        have "$tool" || fail "'$tool' is not installed" "$(fix_hint "$tool")"
        exec sh -c "$*"
        ;;
    gh-ext)
        ext="${1:-}"; shift; [ "${1:-}" = "--" ] && shift
        have gh || retry_with_login_path
        have gh || fail "'gh' (GitHub CLI) is not installed" "$(fix_hint gh)"
        # plain grep, not -q: under pipefail an early exit would look like no match
        if ! gh extension list 2>/dev/null | grep "$ext" >/dev/null; then
            fail "gh extension '$ext' is not installed" "Install it with:  gh extension install dlvhdr/$ext   (or: ~/.config/tmux/update.sh)"
        fi
        exec sh -c "$*"
        ;;
esac
