#!/usr/bin/env bash
# Quick notes manager — create, search, and edit markdown notes
# Notes stored in ~/.local/share/tmux/notes/

NOTES_DIR="$HOME/.local/share/tmux/notes"
mkdir -p "$NOTES_DIR"
export NOTES_DIR

# Extract note name from a "  name  │  preview" line or selection.
# Pure bash — no forks.
note_name() {
    local s="${1#  }"
    echo "${s%% *}"
}
export -f note_name

list_notes() {
    echo "  + New note"
    # Read newest-first; line-based loop handles spaces in filenames safely.
    # shellcheck disable=SC2012  # filenames are sanitized at creation; ls -t needed for portable mtime sort
    ls -t "$NOTES_DIR"/*.md 2>/dev/null | while IFS= read -r f; do
        name=$(basename "$f" .md)
        preview=$(head -1 "$f" | sed 's/^#* *//')
        echo "  $name  │  $preview"
    done
}

preview_note() {
    local f
    f="$NOTES_DIR/$(note_name "$1").md"
    [ -f "$f" ] && cat "$f" || echo "New note"
}
export -f preview_note

while true; do
    selected=$(
        list_notes | fzf --prompt="Notes > " \
            --header="Enter: edit  |  Ctrl-d: mark delete  |  Esc: quit" \
            --expect=ctrl-d \
            --preview="preview_note {}" \
            --preview-window=right:50%:wrap
    )

    [ -z "$selected" ] && exit 0

    # First line is the key pressed, second is the selection
    key=$(echo "$selected" | head -1)
    choice=$(echo "$selected" | tail -1)

    [ -z "$choice" ] && exit 0

    if [ "$key" = "ctrl-d" ]; then
        # Delete with confirmation
        name=$(note_name "$choice")
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
        name=$(note_name "$choice")
        file="$NOTES_DIR/$name.md"
    fi

    ${EDITOR:-vim} "$file"
    break
done
