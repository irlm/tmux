#!/usr/bin/env bash
# Tmux sessionizer — fzf pick a project, jump to or create session
# Searches: ~/projects, ~/.config, and existing tmux sessions

# Gather git repos from ~/projects and ~/.config (skip plugin dirs)
dirs=$(find ~/projects ~/.config -maxdepth 4 -type d -name .git \
    -not -path "*/plugins/*" 2>/dev/null | sed 's|/\.git$||')

# Add existing tmux sessions
sessions=$(tmux list-sessions -F "#{session_name}: #{session_path}" 2>/dev/null)

# Combine and pick with fzf
selected=$(echo "$dirs" | sort -u | fzf --prompt="Project > " \
    --header="Pick a project or session" \
    --preview 'ls -la {} 2>/dev/null | head -20' \
    --preview-window=right:40%)

[ -z "$selected" ] && exit 0

# Clean session name (replace dots/spaces with dashes)
session_name=$(basename "$selected" | tr './ ' '---')

# If session exists, switch to it
if tmux has-session -t="$session_name" 2>/dev/null; then
    tmux switch-client -t "$session_name"
else
    # Create new session and switch
    tmux new-session -d -s "$session_name" -c "$selected"
    tmux switch-client -t "$session_name"
fi
