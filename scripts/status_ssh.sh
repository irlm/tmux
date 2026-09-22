#!/usr/bin/env bash
# Second status line while the active pane holds an ssh session: where to.
#
#   status_ssh.sh toggle <pane_pid>   silent: turn the second line on or off
#   status_ssh.sh line   <pane_pid>   print the line's content
#
# tmux only runs the #() commands of a line it is showing, so a hidden second
# line can never switch itself on. The toggle therefore lives in status-right
# (always shown) and the renderer in status-format[1]. Both get the active
# pane's shell pid and look for an ssh among its children and grandchildren
# — a hand-typed ssh is a child; ssh-remote.sh puts it one level down.
mode="${1:-line}"
pane_pid="${2:-}"
[ -z "$pane_pid" ] && exit 0

find_ssh() {
    local child gchild cmd
    for child in $(pgrep -P "$pane_pid" 2>/dev/null); do
        cmd=$(ps -o command= -p "$child" 2>/dev/null)
        case "$cmd" in ssh\ *|slogin\ *|mosh\ *|mosh-client\ *|autossh\ *|et\ *|tsh\ *) echo "$cmd"; return ;; esac
        for gchild in $(pgrep -P "$child" 2>/dev/null); do
            cmd=$(ps -o command= -p "$gchild" 2>/dev/null)
            case "$cmd" in ssh\ *|slogin\ *|mosh\ *|mosh-client\ *|autossh\ *|et\ *|tsh\ *) echo "$cmd"; return ;; esac
        done
    done
}

ssh_cmd="$(find_ssh)"

if [ "$mode" = "toggle" ]; then
    current=$(tmux show -gqv status 2>/dev/null)
    if [ -z "$ssh_cmd" ]; then
        [ "$current" = "2" ] && tmux set -g status on 2>/dev/null
    else
        [ "$current" != "2" ] && tmux set -g status 2 2>/dev/null
    fi
    exit 0
fi

[ -z "$ssh_cmd" ] && exit 0

# Walk the arguments: skip options (with their value where they take one)
# until the first bare word, which is the destination. Anything after it is
# the remote command.
target=""; port=""
# shellcheck disable=SC2206  # word-splitting the command line is the point
args=($ssh_cmd); unset 'args[0]'
skip=0
for a in "${args[@]}"; do
    if [ "$skip" = "1" ]; then skip=0; continue; fi
    case "$a" in
        -p)  skip=1; port_next=1; continue ;;
        -p*) port="${a#-p}"; continue ;;
        -[iopFJLRDwWeEbcSmBOP]) skip=1; continue ;;   # option with a value
        -*)  continue ;;                               # bare flag(s)
        *)   target="$a"; break ;;
    esac
done
# the value after -p was skipped above; fetch it again
if [ -n "${port_next:-}" ]; then
    port=$(echo "$ssh_cmd" | grep -oE '(^| )-p ?[0-9]+' | grep -oE '[0-9]+$')
fi
[ -z "$target" ] && exit 0

case "$target" in
    *@*) user="${target%%@*}"; host="${target#*@}" ;;
    *)   user="";              host="$target" ;;
esac
out="#[fg=colour2,bold] 󰢹 SSH #[fg=colour4]${host}#[default]"
[ -n "$user" ] && out="${out} #[fg=colour8]as#[default] #[fg=colour3]${user}#[default]"
[ -n "$port" ] && out="${out}#[fg=colour8]:${port}#[default]"
echo "$out"
