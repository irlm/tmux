#!/usr/bin/env bash
# Lightweight net speed — uses a cache file to diff between calls
# Designed to be called every 5s by tmux status-interval

CACHE="/tmp/tmux_net_speed"

human_rate() {
    local bytes=$1
    if [ "$bytes" -ge 1048576 ]; then
        printf "%4sM/s" "$(( bytes / 1048576 ))"
    elif [ "$bytes" -ge 1024 ]; then
        printf "%4sK/s" "$(( bytes / 1024 ))"
    else
        printf "%4sB/s" "$bytes"
    fi
}

# Get current bytes — works on macOS and Linux
if [ -f /proc/net/dev ]; then
    # Linux
    read rx tx <<< $(awk '/:/ && !/lo:/ {rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev)
else
    # macOS — sum all active interfaces
    read rx tx <<< $(netstat -ib 2>/dev/null | awk '/Link/ && !/lo/ {rx+=$7; tx+=$10} END {print rx, tx}')
fi

now=$(date +%s)

if [ -f "$CACHE" ]; then
    read prev_time prev_rx prev_tx < "$CACHE"
    elapsed=$(( now - prev_time ))
    if [ "$elapsed" -gt 0 ] && [ "$elapsed" -lt 30 ]; then
        down=$(( (rx - prev_rx) / elapsed ))
        up=$(( (tx - prev_tx) / elapsed ))
        # Avoid negative on counter reset
        [ "$down" -lt 0 ] && down=0
        [ "$up" -lt 0 ] && up=0
        echo "↓$(human_rate $down) ↑$(human_rate $up)"
    else
        echo "↓0B/s ↑0B/s"
    fi
else
    echo "↓… ↑…"
fi

echo "$now $rx $tx" > "$CACHE"
