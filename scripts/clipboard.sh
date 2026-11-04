#!/usr/bin/env bash
# Copy stdin to the system clipboard with whatever this machine has; without a
# tool, OSC 52 asks the terminal to keep it (works over ssh and inside tmux).
# Used by copy mode (tmux.conf), the pickers and anything else that copies.
if command -v pbcopy >/dev/null 2>&1; then pbcopy
elif command -v wl-copy >/dev/null 2>&1; then wl-copy
elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard
elif command -v xsel >/dev/null 2>&1; then xsel --clipboard --input
elif command -v clip.exe >/dev/null 2>&1; then clip.exe                 # Windows (Git Bash, WSL)
else
    encoded=$(base64 | tr -d '\n')
    if [ -n "${TMUX:-}" ]; then
        # tmux forwards the sequence to the outer terminal (set-clipboard on).
        printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$encoded" > "${TMUX_TTY:-/dev/tty}" 2>/dev/null || printf '\033]52;c;%s\a' "$encoded"
    else
        printf '\033]52;c;%s\a' "$encoded" > /dev/tty 2>/dev/null || printf '\033]52;c;%s\a' "$encoded"
    fi
fi
