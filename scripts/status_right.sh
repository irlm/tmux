#!/usr/bin/env bash
# Build status-right dynamically based on available hardware

PLUGIN_DIR="$HOME/.config/tmux/plugins"
CPU_DIR="$PLUGIN_DIR/tmux-cpu/scripts"
BAT_DIR="$PLUGIN_DIR/tmux-battery/scripts"

out=""
sep=" | "

# Network speed (first — variable width won't shift the rest)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "$SCRIPT_DIR/net_speed.sh" ]; then
    net=$("$SCRIPT_DIR/net_speed.sh")
    [ -n "$net" ] && out="#[fg=magenta]${net}#[default]"
fi

# CPU
if [ -x "$CPU_DIR/cpu_percentage.sh" ]; then
    cpu=$("$CPU_DIR/cpu_percentage.sh")
    [ -n "$cpu" ] && out="${out}${sep}#[fg=cyan]${cpu}#[default]"
fi

# RAM
if [ -x "$CPU_DIR/ram_percentage.sh" ]; then
    ram=$("$CPU_DIR/ram_percentage.sh")
    [ -n "$ram" ] && out="${out}${sep}#[fg=yellow]${ram}#[default]"
fi

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
        upower -i "$battery" | grep -q "state:.*charging" && charging=true
    fi
fi

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
        color="green"
    elif [ "$batt_pct" -ge 20 ]; then
        color="yellow"
    else
        color="red"
    fi
    out="${out}${sep}#[fg=${color}]${icon} ${batt_pct}%#[default]"
fi

# Date/time
out="${out}${sep}$(date +'%a %d %b %H:%M') "

echo "$out"
