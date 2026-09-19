#!/usr/bin/env bash
# SSH to a host and land in its tmux. When the host doesn't have this config
# yet, offer to install it there first — the same install.sh this machine
# uses, in --server mode. While the window is open, the local prefix is
# switched off (see remote-mode.sh) so C-a and friends reach the remote tmux.
#
#   ssh-remote.sh <host>      host is anything ssh accepts (alias, user@host)

host="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$SCRIPT_DIR/../install.sh"
REMOTE_MODE="$SCRIPT_DIR/remote-mode.sh"

# The window closes when this script ends, so errors have to wait for a key.
pause_exit() {
    echo ""
    read -rp "Press Enter to close..." _
    exit "${1:-0}"
}

if [ -z "$host" ]; then
    echo "usage: ssh-remote.sh <host>"
    pause_exit 1
fi

# Share one connection between the probe, the install and the attach, so a
# password or passphrase is asked for once instead of three times.
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$HOME/.ssh/tmux-cm-%C" -o ControlPersist=120)

# Run a snippet in the remote user's login shell, so PATH matches what they
# get interactively (~/.local/bin, Homebrew, ...) rather than sshd's bare one.
remote_sh() {
    ssh "${SSH_OPTS[@]}" -o ConnectTimeout=10 "$host" 'exec "${SHELL:-sh}" -l -s'
}

probe() {
    remote_sh <<'PROBE'
command -v tmux >/dev/null 2>&1 && echo HAS_TMUX
[ -f "$HOME/.config/tmux/tmux.conf" ] && echo HAS_CONFIG
echo PROBE_OK
PROBE
}

echo "Connecting to $host..."
state="$(probe)"
case "$state" in
    *PROBE_OK*) ;;
    *)
        echo "Could not connect to $host."
        pause_exit 1
        ;;
esac

# ─── Bootstrap ────────────────────────────────────────────
case "$state" in
    *HAS_CONFIG*) ;;
    *)
        echo ""
        echo "$host doesn't have this tmux config yet."
        read -rp "Install it there now (server mode: tmux, neovim, fzf, bat, btop)? [Y/n] " answer
        answer="${answer:-Y}"
        if [[ "$answer" =~ ^[Yy] ]]; then
            if [ -f "$INSTALLER" ]; then
                # Ship this machine's installer so both ends run the same version.
                remote_tmp=$(ssh "${SSH_OPTS[@]}" "$host" 'mktemp "${TMPDIR:-/tmp}/tmux-install.XXXXXX"' 2>/dev/null)
                if [ -n "$remote_tmp" ] && ssh "${SSH_OPTS[@]}" "$host" "cat > '$remote_tmp'" < "$INSTALLER"; then
                    # -t: server mode uses sudo, which needs a terminal to ask on
                    ssh -t "${SSH_OPTS[@]}" "$host" "bash '$remote_tmp' --server; rc=\$?; rm -f '$remote_tmp'; exit \$rc" \
                        || echo "Installer reported errors — see output above."
                else
                    echo "Could not copy the installer to $host."
                fi
            else
                ssh -t "${SSH_OPTS[@]}" "$host" \
                    'curl -fsSL https://raw.githubusercontent.com/irlm/tmux/main/install.sh | bash -s -- --server' \
                    || echo "Installer reported errors — see output above."
            fi
            state="$(probe)"
        fi
        ;;
esac

# ─── Attach ───────────────────────────────────────────────
case "$state" in
    *HAS_TMUX*)
        # Mark the window remote and hand the keyboard to the inner tmux. The
        # session-window-changed hook keeps this in step as windows change.
        if [ -n "${TMUX_PANE:-}" ]; then
            tmux set -w -t "$TMUX_PANE" @remote 1
            "$REMOTE_MODE" auto "$TMUX_PANE"
        fi
        ssh -t "${SSH_OPTS[@]}" "$host" 'exec "${SHELL:-sh}" -l -c "tmux attach 2>/dev/null || tmux new"'
        rc=$?
        if [ -n "${TMUX_PANE:-}" ]; then
            tmux set -w -u -t "$TMUX_PANE" @remote
            "$REMOTE_MODE" auto "$TMUX_PANE"
        fi
        [ "$rc" -eq 255 ] && { echo "Connection to $host lost."; pause_exit "$rc"; }
        ;;
    *)
        echo ""
        echo "No tmux on $host — opening a plain shell."
        ssh -t "${SSH_OPTS[@]}" "$host"
        ;;
esac
