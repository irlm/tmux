#!/usr/bin/env bash
# Quick notes manager — create, search, and edit markdown notes
# Notes stored in ~/.local/share/tmux/notes/

NOTES_DIR="$HOME/.local/share/tmux/notes"
mkdir -p "$NOTES_DIR"

list_notes() {
    echo "  + New note"
    for f in $(ls -t "$NOTES_DIR"/*.md 2>/dev/null); do
        name=$(basename "$f" .md)
        preview=$(head -1 "$f" | sed 's/^#* *//')
        echo "  $name  │  $preview"
    done
}

while true; do
    selected=$(
        list_notes | fzf --prompt="Notes > " \
            --header="Enter: edit  |  Ctrl-d: mark delete  |  Esc: quit" \
            --expect=ctrl-d \
            --preview='f="$HOME/.local/share/tmux/notes/$(echo {} | sed "s/^  //" | cut -d" " -f1).md"; [ -f "$f" ] && cat "$f" || echo "New note"' \
            --preview-window=right:50%:wrap
    )

    [ -z "$selected" ] && exit 0

    # First line is the key pressed, second is the selection
    key=$(echo "$selected" | head -1)
    choice=$(echo "$selected" | tail -1)

    [ -z "$choice" ] && exit 0

    if [ "$key" = "ctrl-d" ]; then
        # Delete with confirmation
        name=$(echo "$choice" | sed 's/^  //' | cut -d' ' -f1)
        file="$NOTES_DIR/$name.md"
        if [ -f "$file" ]; then
            printf "Delete '%s'? [y/N] " "$name"
            read -rsn1 ans
            echo ""
            if [ "$ans" = "y" ]; then
                rm "$file"
                echo "Deleted."
                sleep 0.5
            fi
        fi
        # Loop back to fzf
        continue
    fi

    # Edit or create
    if echo "$choice" | grep -q "+ New note"; then
        printf "Note name (or Enter for date): "
        read -r name
        if [ -z "$name" ]; then
            name=$(date +"%Y-%m-%d_%H%M")
        fi
        name=$(echo "$name" | tr ' /' '-_' | tr -cd '[:alnum:]_-')
        file="$NOTES_DIR/$name.md"
        echo "# $name" > "$file"
        echo "" >> "$file"
    else
        name=$(echo "$choice" | sed 's/^  //' | cut -d' ' -f1)
        file="$NOTES_DIR/$name.md"
    fi

    ${EDITOR:-vim} "$file"
    break
done
