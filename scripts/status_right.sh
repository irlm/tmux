#!/usr/bin/env bash
# Build status-right dynamically based on available hardware

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
CPU_DIR="$TMUX_CONFIG_DIR/plugins/tmux-cpu/scripts"
# --plain: no tmux colour directives, for hosts that strip escapes (Herdr's
# tab bar shows the last line of output as plain text).
# --part net|cpu|ram|battery|holiday: only that reading, for a host that
# colours whole entries (a Herdr with per-entry colours). The sample and its
# cache are shared, so several parts still cost one measurement.
paint=1; part=""
while [ $# -gt 0 ]; do
    case "$1" in
        --plain) paint=0; shift ;;
        --part) part=${2:-}; shift 2 ;;
        *) break ;;
    esac
done
width=${1:-160}
case "$width" in ''|*[!0-9]*) width=160 ;; esac
[ "$width" -ge 100 ] || exit 0
private_dir "$TMUX_CACHE_DIR" || exit 0
read -r now today <<< "$(date '+%s %F')"
cpu_icon=""; ram_icon="󰍛"
sep=" | "

# Readings are joined with sep in a fixed order; --part picks one back out by
# the marker each carries in plain mode (net arrows, cpu and ram icons or
# their ASCII labels, a percentage for the battery, whatever is left for the
# special-day motif).
select_part() {
    local line=$1 segment kind
    [ -n "$part" ] || { printf '%s\n' "$line"; return; }
    while IFS= read -r segment; do
        [ -n "$segment" ] || continue
        if [[ "$segment" == *↓* ]]; then kind=net
        elif [[ "$segment" == "$cpu_icon "* || "$segment" == CPU* ]]; then kind=cpu
        elif [[ "$segment" == "$ram_icon "* || "$segment" == RAM* ]]; then kind=ram
        elif [[ "$segment" == *% ]]; then kind=battery
        else kind=holiday; fi
        if [ "$kind" = "$part" ]; then printf '%s\n' "$segment"; return; fi
    done <<< "${line//$sep/$'\n'}"
}
if [ "$(wb_backend)" = tmux ]; then
    info=$(tmux display-message -p '#{@ascii}|#{@theme}|#{@theme_magenta}|#{@theme_accent}|#{@theme_yellow}|#{@theme_green}|#{@theme_red}|#{@special_days}' 2>/dev/null) || info=""
else
    info="$(tmux_option @ascii)|$(tmux_option @theme)|||||||$(tmux_option @special_days)"
fi
IFS='|' read -r ascii theme_id magenta accent yellow green red special_days <<< "$info"
# paint <colour> <text>: a tmux style span, or the bare text in --plain mode.
paint() { if [ "$paint" -eq 1 ]; then printf '#[fg=%s]%s#[default]' "$1" "$2"; else printf '%s' "$2"; fi; }
ascii=${ascii:-off}; theme_id=${theme_id:-nord}
case "$theme_id" in *[!a-z0-9-]*|'') theme_id=nord ;; esac
magenta=${magenta:-#d4a9ca}; accent=${accent:-#88c0d0}; yellow=${yellow:-#ebcb8b}
green=${green:-#a3be8c}; red=${red:-#f2a1a8}
case "$ascii" in on|off) ;; *) ascii=off ;; esac
export TMUX_ASCII="$ascii"
case "$special_days" in off) ;; *) special_days=on ;; esac
cache="$TMUX_CACHE_DIR/status-$theme_id-$ascii-$special_days-$paint"
if [ -f "$cache" ]; then
    read -r sampled sampled_day < "$cache"
    if [ "$sampled_day" = "$today" ] && [[ "$sampled" =~ ^[0-9]+$ ]] && [ "$((now - sampled))" -ge 0 ] && [ "$((now - sampled))" -lt 5 ]; then
        select_part "$(tail -n +2 "$cache")"
        exit 0
    fi
fi

out=""

# Network speed (first — variable width won't shift the rest)
if [ -x "$SCRIPT_DIR/net_speed.sh" ]; then
    net=$("$SCRIPT_DIR/net_speed.sh")
    [ -n "$net" ] && out=$(paint "$magenta" "$net")
fi

# CPU
if [ -x "$CPU_DIR/cpu_percentage.sh" ]; then
    cpu=$("$CPU_DIR/cpu_percentage.sh")
    # Without colours (Herdr's tab bar) an icon says which reading is which.
if [ "$paint" -eq 0 ] && [ -n "$cpu" ]; then
    if [ "$ascii" = on ]; then cpu="CPU $cpu"; else cpu="$cpu_icon $cpu"; fi
fi
[ -n "$cpu" ] && out="${out}${sep}$(paint "$accent" "$cpu")"
fi

# RAM (actual usage, not file cache — matches btop/Activity Monitor)
ram=""
if command -v vm_stat &>/dev/null; then
    # macOS: Activity Monitor's "Memory Used" is app memory (anonymous pages
    # minus purgeable) plus wired and compressed pages. memory_pressure's
    # "free percentage" counts file cache and inactive pages as free, so it
    # showed 7% while btop showed 45%.
    ram=$(vm_stat 2>/dev/null | awk -v total="$(sysctl -n hw.memsize 2>/dev/null)" '
        /page size of/ { page = $8 }
        /^Anonymous pages:/ { anon = $3 }
        /^Pages purgeable:/ { purgeable = $3 }
        /^Pages wired down:/ { wired = $4 }
        /^Pages occupied by compressor:/ { compressed = $5 }
        END { if (page > 0 && total > 0) printf "%.0f%%", 100 * (anon - purgeable + wired + compressed) * page / total }')
elif command -v free &>/dev/null; then
    # Linux: use "available" column (free + reclaimable cache)
    # Falls back to used/total if "available" column is missing (older kernels)
    ram=$(free | awk '/Mem/ { if ($7 > 0) printf "%.0f%%", 100 * ($2 - $7) / $2; else printf "%.0f%%", 100 * $3 / $2 }')
fi
if [ "$paint" -eq 0 ] && [ -n "$ram" ]; then
    if [ "$ascii" = on ]; then ram="RAM $ram"; else ram="$ram_icon $ram"; fi
fi
[ -n "$ram" ] && out="${out}${sep}$(paint "$yellow" "$ram")"

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
    out="${out}${sep}$(paint "$color" "${icon} ${batt_pct}%")"
fi

# A small ASCII drawing sits next to the native clock on special days.
# The motif only changes with the date, so the lookup runs once per day.
if [ "$special_days" = on ]; then
    holiday_cache="$TMUX_CACHE_DIR/holiday"
    holiday_day=""; holiday=""
    if [ -f "$holiday_cache" ]; then
        { IFS= read -r holiday_day; IFS= read -r holiday; } < "$holiday_cache" || true
    fi
    if [ "$holiday_day" != "$today" ]; then
        if holiday=$(python3 "$SCRIPT_DIR/special_days.py" --status --date "$today" 2>/dev/null); then
            tmp=$(mktemp "$TMUX_CACHE_DIR/holiday.XXXXXX")
            printf '%s\n%s\n' "$today" "$holiday" > "$tmp"
            mv -f -- "$tmp" "$holiday_cache"
        else
            holiday=""
        fi
    fi
    [ -z "$holiday" ] || out="${out}${sep}$(paint "$accent" "$holiday")"
fi

# Date/time is rendered natively by tmux, outside this cached sample.
tmp=$(mktemp "$TMUX_CACHE_DIR/status.XXXXXX")
printf '%s %s\n%s\n' "$now" "$today" "$out" > "$tmp"
mv -f -- "$tmp" "$cache"
select_part "$out"
