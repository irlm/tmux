#!/usr/bin/env bash
# Run a tool inside a tmux popup, or say why it cannot.
#
#   popup.sh <command> [args...]
#
# A popup whose command is missing closes the instant it opens, which reads
# as "the key does nothing". This keeps the popup up with the reason and the
# way to fix it instead. Also tries a login shell's PATH before giving up,
# for tools installed after the tmux server started.
cmd="${1:-}"
[ -z "$cmd" ] && exit 1

if ! command -v "$cmd" >/dev/null 2>&1; then
    login_path=$("${SHELL:-sh}" -lc 'printf %s "$PATH"' 2>/dev/null)
    [ -n "$login_path" ] && export PATH="$login_path:$PATH"
fi

if command -v "$cmd" >/dev/null 2>&1; then
    exec "$@"
fi

echo ""
echo "  '$cmd' is not installed on $(hostname -s 2>/dev/null || hostname)."
echo ""
case "$cmd" in
    lazygit|lazydocker|btop|fastfetch|bat|fzf|rg|fd|tldr|zoxide)
        echo "  Install it with:  ~/.config/tmux/update.sh --fix" ;;
    gh)
        echo "  Install it with:  ~/.config/tmux/update.sh --fix" ;;
esac
echo ""
read -rp "  Press Enter to close..." _
exit 127
