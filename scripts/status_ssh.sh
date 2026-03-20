#!/usr/bin/env bash
# Detect SSH in active pane — toggle second status line on/off
# Called by status-format[1] every status-interval

pane_pid="$1"
[ -z "$pane_pid" ] && exit 0

# Find SSH process: check children and grandchildren of the pane shell
ssh_cmd=""
for child in $(pgrep -P "$pane_pid" 2>/dev/null) "$pane_pid"; do
    cmd=$(ps -o command= -p "$child" 2>/dev/null)
    if echo "$cmd" | grep -qE '^ssh '; then
        ssh_cmd="$cmd"
        break
    fi
    # Check grandchildren
    for gchild in $(pgrep -P "$child" 2>/dev/null); do
        cmd=$(ps -o command= -p "$gchild" 2>/dev/null)
        if echo "$cmd" | grep -qE '^ssh '; then
            ssh_cmd="$cmd"
            break 2
        fi
    done
done

current=$(tmux show -gqv status 2>/dev/null)

if [ -z "$ssh_cmd" ]; then
    # No SSH — hide second bar
    [ "$current" != "on" ] && tmux set -g status on 2>/dev/null
    exit 0
fi

# SSH detected — ensure second bar is visible
[ "$current" != "2" ] && tmux set -g status 2 2>/dev/null

# Extract user@host
target=$(echo "$ssh_cmd" | sed 's/^ssh //' \
    | sed -E 's/-[iopFJLRDwWeEbcSmBO] [^ ]+//g' \
    | sed -E 's/-[46AaCfGgKkMNnqsTtVvXxYy]//g' \
    | tr -s ' ' | sed 's/^ //' | awk '{print $1}')

[ -z "$target" ] && exit 0

if echo "$target" | grep -q '@'; then
    user=$(echo "$target" | cut -d'@' -f1)
    host=$(echo "$target" | cut -d'@' -f2)
else
    user=""
    host="$target"
fi

port=$(echo "$ssh_cmd" | grep -oE '\-p [0-9]+' | awk '{print $2}')

# Build output
out="#[fg=colour2,bold]  SSH #[fg=colour4]${host}#[default]"
[ -n "$user" ] && out="${out} #[fg=colour8]as#[default] #[fg=colour3]${user}#[default]"
[ -n "$port" ] && out="${out}#[fg=colour8]:${port}#[default]"

echo "$out"
