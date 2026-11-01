#!/usr/bin/env bash
# Private, atomic samples; repeated renders in one second reuse the last rate.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
private_dir "$TMUX_CACHE_DIR" || exit 1
CACHE="$TMUX_CACHE_DIR/network"
human_rate() {
    local bytes=$1
    if [ "$bytes" -ge 1048576 ]; then printf '%4sM/s' "$((bytes / 1048576))";
    elif [ "$bytes" -ge 1024 ]; then printf '%4sK/s' "$((bytes / 1024))";
    else printf '%4sB/s' "$bytes"; fi
}
if [ -f /proc/net/dev ]; then
    read -r rx tx < <(awk '/:/ && !/lo:/ {rx+=$2; tx+=$10} END {printf "%.0f %.0f\n", rx, tx}' /proc/net/dev)
else
    read -r rx tx < <(netstat -ib 2>/dev/null | awk '/Link/ && !/lo/ {rx+=$7; tx+=$10} END {printf "%.0f %.0f\n", rx, tx}')
fi
now=$(date +%s)
down=0; up=0
if [ -f "$CACHE" ]; then
    read -r previous prev_rx prev_tx prev_down prev_up < "$CACHE" || true
    if [[ "${previous:-} ${prev_rx:-} ${prev_tx:-} ${prev_down:-} ${prev_up:-}" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ ]]; then
        elapsed=$((now - previous))
        if [ "$elapsed" -eq 0 ]; then
            down=$prev_down; up=$prev_up
        elif [ "$elapsed" -gt 0 ] && [ "$elapsed" -lt 30 ] && [ "$rx" -ge "$prev_rx" ] && [ "$tx" -ge "$prev_tx" ]; then
            down=$(((rx - prev_rx) / elapsed)); up=$(((tx - prev_tx) / elapsed))
        fi
    fi
fi
icons=${TMUX_ASCII:-off}
if [ "$icons" = on ]; then printf 'D%s U%s\n' "$(human_rate "$down")" "$(human_rate "$up")";
else printf '↓%s ↑%s\n' "$(human_rate "$down")" "$(human_rate "$up")"; fi
sample=$(mktemp "$TMUX_CACHE_DIR/network.XXXXXX") || exit 1
printf '%s %s %s %s %s\n' "$now" "$rx" "$tx" "$down" "$up" > "$sample"
mv -f -- "$sample" "$CACHE"
