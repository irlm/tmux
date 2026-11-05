#!/usr/bin/env bash
# A worktree per task: pick an existing worktree of this repository, or type
# a branch name to create one, and land in it as its own Herdr workspace
# (grouped under this one) or tmux session. Both use the same directory
# layout, <worktree_dir>/<repo>/<branch>, so a checkout made under one
# multiplexer is listed under the other. C-a C-g.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
backend=$(wb_backend)
root=$(git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || { echo 'Not a Git repository.'; pause_close; exit 1; }
root=$(git -C "$root" worktree list --porcelain | sed -n '1s/^worktree //p')   # the main checkout
repo=$(basename "$root")
base=$(tmux_option @worktree_dir "$HOME/.herdr/worktrees"); base=${base/#\~/$HOME}
command -v fzf >/dev/null 2>&1 || { "$SCRIPT_DIR/popup.sh" fzf; exit $?; }

existing() {   # path<TAB>branch   path (the main checkout first)
    git -C "$root" worktree list --porcelain | awk -v home="$HOME" '
        /^worktree / { path = substr($0, 10) }
        /^branch / { branch = substr($0, 8); sub("^refs/heads/", "", branch) }
        /^detached/ { branch = "(detached)" }
        /^$/ && path != "" { shown = path; sub("^" home, "~", shown); printf "%s\t%-28s %s\n", path, branch, shown; path = ""; branch = "" }
        END { if (path != "") { shown = path; sub("^" home, "~", shown); printf "%s\t%-28s %s\n", path, branch, shown } }'
}

picked=$(existing | fzf --delimiter=$'\t' --with-nth=2.. --tabstop=1 --no-sort --print-query \
    --prompt="Worktree of $repo > " \
    --header='Enter: open the worktree · type a new branch name and Enter to create it')
rc=$?
query=${picked%%$'\n'*}
[ "$rc" -ne 130 ] || exit 0
selection=""
case "$picked" in *$'\n'*) selection=${picked#*$'\n'}; selection=${selection%%$'\t'*} ;; esac
if [ -n "$selection" ] && [ "$rc" -eq 0 ]; then
    path=$selection; branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$(basename "$path")")
else
    branch=$query
    [ -n "$branch" ] || exit 0
    case "$branch" in -*|*[[:space:]]*|*..*) echo "Not a branch name: $branch"; pause_close; exit 1 ;; esac
    path=""
fi

case "$backend" in
    herdr)
        if [ -n "$path" ] && [ "$path" != "$root" ]; then
            herdr worktree open --cwd "$root" --path "$path" --focus >/dev/null || { pause_close; exit 1; }
        elif [ -n "$path" ]; then
            echo 'That is the main checkout; pick another worktree or type a branch name.'; pause_close; exit 0
        else
            herdr worktree create --cwd "$root" --branch "$branch" --focus >/dev/null || { pause_close; exit 1; }
        fi ;;
    tmux)
        if [ -z "$path" ]; then
            slug=$(printf '%s' "$branch" | tr '/' '-')
            path="$base/$repo/$slug"
            if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
                git -C "$root" worktree add "$path" "$branch" || { pause_close; exit 1; }
            else
                git -C "$root" worktree add -b "$branch" "$path" || { pause_close; exit 1; }
            fi
        fi
        session=$(printf '%s' "$repo-$(basename "$path")" | tr '.:' '__')
        tmux has-session -t "=$session" 2>/dev/null || tmux new-session -d -s "$session" -c "$path"
        tmux switch-client -t "=$session" ;;
    *) echo 'Not inside Herdr or tmux.' >&2; exit 1 ;;
esac
