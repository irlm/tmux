#!/usr/bin/env bash
# Make per-user tool directories visible to everything tmux starts.
#
# Popups, run-shell and new panes inherit the tmux *server's* environment,
# which is whatever shell started the server — often without ~/.local/bin
# (where install.sh --server puts bat, fd, rg, lazygit, ...) or the JDK and
# Coursier directories. So C-a g would fail on a machine that has lazygit.
# Run from tmux.conf at load; safe to re-run, adds each directory once.
# Each is prepended in turn, so later entries end up first: user-level
# directories win over Homebrew, which wins over whatever was there.
dirs=(
    /usr/local/bin
    /opt/homebrew/bin
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    /opt/homebrew/opt/openjdk/bin
    /usr/local/opt/openjdk/bin
    "$HOME/Library/Application Support/Coursier/bin"
    "$HOME/.local/share/coursier/bin"
)
changed=0
for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    case ":$PATH:" in
        *":$d:"*) ;;
        *) PATH="$d:$PATH"; changed=1 ;;
    esac
done
[ "$changed" = "1" ] || exit 0

# The server's own PATH may not reach the tmux binary either (Homebrew's
# /opt/homebrew/bin, say), so look in the usual places before giving up.
for t in tmux /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
    if command -v "$t" >/dev/null 2>&1; then
        "$t" set-environment -g PATH "$PATH"
        break
    fi
done
exit 0
