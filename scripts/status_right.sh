#!/usr/bin/env bash
# Build status-right dynamically based on available hardware

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
CPU_DIR="$TMUX_CONFIG_DIR/plugins/tmux-cpu/scripts"
width=${1:-160}
case "$width" in ''|*[!0-9]*) width=160 ;; esac
[ "$width" -ge 100 ] || exit 0
private_dir "$TMUX_CACHE_DIR" || exit 0
now=$(date +%s)
info=$(tmux display-message -p '#{@ascii}|#{@theme}|#{@theme_magenta}|#{@theme_accent}|#{@theme_yellow}|#{@theme_green}|#{@theme_red}' 2>/dev/null) || info=""
IFS='|' read -r ascii theme_id magenta accent yellow green red <<< "$info"
ascii=${ascii:-off}; theme_id=${theme_id:-nord}
case "$theme_id" in *[!a-z0-9-]*|'') theme_id=nord ;; esac
magenta=${magenta:-#d4a9ca}; accent=${accent:-#88c0d0}; yellow=${yellow:-#ebcb8b}
green=${green:-#a3be8c}; red=${red:-#f2a1a8}
case "$ascii" in on|off) ;; *) ascii=off ;; esac
export TMUX_ASCII="$ascii"
cache="$TMUX_CACHE_DIR/status-$theme_id-$ascii"
if [ -f "$cache" ]; then
    IFS= read -r sampled < "$cache"
    if [[ "$sampled" =~ ^[0-9]+$ ]] && [ "$((now - sampled))" -ge 0 ] && [ "$((now - sampled))" -lt 5 ]; then
        tail -n +2 "$cache"
        exit 0
    fi
fi

out=""
sep=" | "

# Network speed (first — variable width won't shift the rest)
if [ -x "$SCRIPT_DIR/net_speed.sh" ]; then
    net=$("$SCRIPT_DIR/net_speed.sh")
    [ -n "$net" ] && out="#[fg=${magenta}]${net}#[default]"
fi

# CPU
if [ -x "$CPU_DIR/cpu_percentage.sh" ]; then
    cpu=$("$CPU_DIR/cpu_percentage.sh")
    [ -n "$cpu" ] && out="${out}${sep}#[fg=${accent}]${cpu}#[default]"
fi

# RAM (actual usage, not file cache — matches btop/Activity Monitor)
ram=""
if command -v memory_pressure &>/dev/null; then
    # macOS: use memory_pressure to get system-wide free %, invert to used
    pct_free=$(memory_pressure 2>/dev/null | awk '/free percentage/ {gsub(/%/,""); print $NF}')
    [ -n "$pct_free" ] && ram=$(awk "BEGIN {printf \"%.0f%%\", 100 - $pct_free}")
elif command -v free &>/dev/null; then
    # Linux: use "available" column (free + reclaimable cache)
    # Falls back to used/total if "available" column is missing (older kernels)
    ram=$(free | awk '/Mem/ { if ($7 > 0) printf "%.0f%%", 100 * ($2 - $7) / $2; else printf "%.0f%%", 100 * $3 / $2 }')
fi
[ -n "$ram" ] && out="${out}${sep}#[fg=${yellow}]${ram}#[default]"

# Battery capabilities and readings change much less often than network/CPU.
battery_cache="$TMUX_CACHE_DIR/battery"
has_battery=false; charging=false; batt_pct=0; battery_time=0
if [ -f "$battery_cache" ]; then
    read -r battery_time has_battery charging batt_pct < "$battery_cache" || true
fi
if ! [[ "$battery_time" =~ ^[0-9]+$ ]] || [ "$((now - battery_time))" -lt 0 ] || [ "$((now - battery_time))" -ge 60 ]; then
# Battery (only if hardware exists)
has_battery=false
charging=false
batt_pct=0
if command -v pmset &>/dev/null; then
    batt_line=$(pmset -g batt)
    if echo "$batt_line" | grep -q "InternalBattery"; then
        has_battery=true
        batt_pct=$(echo "$batt_line" | grep -o '[0-9]\{1,3\}%' | tr -d '%')
        echo "$batt_line" | grep -q "AC Power" && charging=true
    fi
elif command -v acpi &>/dev/null; then
    batt_line=$(acpi -b 2>/dev/null)
    if echo "$batt_line" | grep -q "Battery"; then
        has_battery=true
        batt_pct=$(echo "$batt_line" | grep -o '[0-9]\{1,3\}%' | head -1 | tr -d '%')
        echo "$batt_line" | grep -q "Charging" && charging=true
    fi
elif command -v upower &>/dev/null; then
    battery=$(upower -e 2>/dev/null | grep battery | head -1)
    if [ -n "$battery" ]; then
        has_battery=true
        batt_pct=$(upower -i "$battery" | awk '/percentage:/ {print $2}' | tr -d '%')
        upower -i "$battery" | grep -q "state: *charging" && charging=true
    fi
fi

    tmp=$(mktemp "$TMUX_CACHE_DIR/battery.XXXXXX")
    printf '%s %s %s %s\n' "$now" "$has_battery" "$charging" "${batt_pct:-0}" > "$tmp"
    mv -f -- "$tmp" "$battery_cache"
fi
case "$has_battery" in true|false) ;; *) has_battery=false ;; esac
case "$charging" in true|false) ;; *) charging=false ;; esac
[[ "$batt_pct" =~ ^[0-9]+$ ]] || batt_pct=0

if $has_battery && [ -n "$batt_pct" ]; then
    if $charging; then
        icon="⚡"
    elif [ "$batt_pct" -ge 90 ]; then
        icon="󰁹"
    elif [ "$batt_pct" -ge 80 ]; then
        icon="󰂂"
    elif [ "$batt_pct" -ge 70 ]; then
        icon="󰂁"
    elif [ "$batt_pct" -ge 60 ]; then
        icon="󰂀"
    elif [ "$batt_pct" -ge 50 ]; then
        icon="󰁿"
    elif [ "$batt_pct" -ge 40 ]; then
        icon="󰁾"
    elif [ "$batt_pct" -ge 30 ]; then
        icon="󰁽"
    elif [ "$batt_pct" -ge 20 ]; then
        icon="󰁼"
    elif [ "$batt_pct" -ge 10 ]; then
        icon="󰁻"
    else
        icon="󰁺"
    fi
    if [ "$batt_pct" -ge 50 ]; then
        color="$green"
    elif [ "$batt_pct" -ge 20 ]; then
        color="$yellow"
    else
        color="$red"
    fi
    [ "$ascii" != on ] || icon=BAT
    out="${out}${sep}#[fg=${color}]${icon} ${batt_pct}%#[default]"
fi

# Date/time is rendered natively by tmux, outside this cached sample.
tmp=$(mktemp "$TMUX_CACHE_DIR/status.XXXXXX")
printf '%s\n%s\n' "$now" "$out" > "$tmp"
mv -f -- "$tmp" "$cache"
printf '%s\n' "$out"
