#!/usr/bin/env bash
# Quick notes manager — create, search, and edit markdown notes
# Notes stored in ~/.local/share/tmux/notes/

NOTES_DIR="$HOME/.local/share/tmux/notes"
mkdir -p "$NOTES_DIR"

# List existing notes + option to create new
selected=$(
    {
        echo "  + New note"
        # List notes: newest first, show date and first line
        for f in $(ls -t "$NOTES_DIR"/*.md 2>/dev/null); do
            name=$(basename "$f" .md)
            preview=$(head -1 "$f" | sed 's/^#* *//')
            echo "  $name  │  $preview"
        done
    } | fzf --prompt="Notes > " \
        --header="Enter: edit  |  Ctrl-d: delete  |  Esc: cancel" \
        --preview='f="$HOME/.local/share/tmux/notes/$(echo {} | sed "s/^  //" | cut -d" " -f1).md"; [ -f "$f" ] && cat "$f" || echo "New note"' \
        --preview-window=right:50%:wrap \
        --bind='ctrl-d:execute(f="$HOME/.local/share/tmux/notes/$(echo {} | sed "s/^  //" | cut -d" " -f1).md"; [ -f "$f" ] && { printf "Delete $(basename "$f")? [y/N] "; read -rsn1 ans; [ "$ans" = "y" ] && rm "$f" && echo " Deleted" || echo " Cancelled"; })+reload(echo "  + New note"; for f in $(ls -t "$HOME/.local/share/tmux/notes/"*.md 2>/dev/null); do name=$(basename "$f" .md); preview=$(head -1 "$f" | sed "s/^#* *//"); echo "  $name  │  $preview"; done)'
)

[ -z "$selected" ] && exit 0

if echo "$selected" | grep -q "+ New note"; then
    # Prompt for note name
    printf "Note name (or Enter for date): "
    read -r name
    if [ -z "$name" ]; then
        name=$(date +"%Y-%m-%d_%H%M")
    fi
    # Sanitize filename
    name=$(echo "$name" | tr ' /' '-_' | tr -cd '[:alnum:]_-')
    file="$NOTES_DIR/$name.md"
    echo "# $name" > "$file"
    echo "" >> "$file"
else
    # Extract filename from selection
    name=$(echo "$selected" | sed 's/^  //' | cut -d' ' -f1)
    file="$NOTES_DIR/$name.md"
fi

# Open in editor
${EDITOR:-vim} "$file"
