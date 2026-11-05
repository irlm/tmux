#!/usr/bin/env bash
# The agent features, live, against a throwaway Herdr session (wbtest): the
# event hook, the sidebar token, the journal, C-a w, the review preview and
# agent-send. Any machine with Herdr and Git Bash or a Unix shell; it never
# touches the default session. Run: bash ~/.config/tmux/tests/herdr-live-check.sh
set -uo pipefail
T="${TMUX_CONFIG_DIR:-$HOME/.config/tmux}"; export PATH="$HOME/scoop/shims:$HOME/.local/bin:$PATH"
PY=$(command -v python3 || command -v python) || { echo "FAIL python missing"; exit 1; }
command -v herdr >/dev/null 2>&1 || { echo "FAIL herdr missing"; exit 1; }
H() { herdr --session wbtest "$@"; }
repo=$(mktemp -d)/repo; git init -q "$repo" && cd "$repo" && printf 'a\nb\n' > f.txt && git add f.txt && git -c user.email=t@t -c user.name=t commit -q -m one && printf 'a\nc\nd\n' > f.txt && echo new > g.txt
cd "$T" || exit 1
# a fresh session: old layouts would pile up
H server stop >/dev/null 2>&1; rm -rf "$HOME/.config/herdr/sessions/wbtest"
(herdr --session wbtest server >/tmp/wbtest.log 2>&1 &)
# no grep -q in a pipeline here: with pipefail its early exit fails the loop
for _ in $(seq 1 120); do case "$(H status server 2>/dev/null)" in *"status: running"*) break ;; esac; sleep 0.5; done
case "$(H status server 2>/dev/null)" in *"status: running"*) echo "PASS server up" ;; *) echo "FAIL server did not start"; head -5 /tmp/wbtest.log; exit 1 ;; esac
created=$(H workspace create --cwd "$repo" --label agtest --no-focus)
pane=$(printf '%s' "$created" | "$PY" -c 'import json,sys;print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])')
ws=${pane%%:*}; echo "pane=$pane ws=$ws"
sleep 2
H pane report-agent "$pane" --source wbtest --agent claude --state working >/dev/null 2>&1; sleep 1
H pane report-agent "$pane" --source wbtest --agent claude --state idle >/dev/null 2>&1; sleep 6
logs=$(H plugin log list --plugin irlm.workbench 2>/dev/null)
printf '%s' "$logs" | "$PY" -c 'import json,sys
try:
    logs=json.load(sys.stdin)["result"]["logs"]
except Exception as e:
    print("FAIL plugin log unreadable", e); sys.exit(0)
ev=[l for l in logs if l.get("event")=="pane.agent_status_changed"]
print(("PASS" if ev else "FAIL")+" event hook ran %d time(s)" % len(ev))
for l in ev[:2]: print("   status=%s exit=%s stderr=%s" % (l.get("status"), l.get("exit_code"), (l.get("stderr") or "")[:160].replace("\n"," | ")))'
H workspace get "$ws" 2>/dev/null | "$PY" -c 'import json,sys
w=json.load(sys.stdin)["result"]["workspace"]; t=w.get("tokens",{})
print(("PASS" if t.get("changes") else "FAIL")+" workspace token changes=%r" % t.get("changes"))'
j="$HOME/.local/share/tmux/agent-journal.tsv"; [ -s "$j" ] && echo "PASS journal: $(tail -1 "$j")" || echo "FAIL journal missing"
out=$(WB_HERDR_SESSION=wbtest HERDR_ENV=1 bash "$T/scripts/agents.sh" --list 2>&1); case "$out" in *"$pane"*) echo "PASS agents list: $(printf '%s' "$out" | head -1 | cut -c1-80)";; *) echo "FAIL agents list: $out";; esac
out=$(cd "$repo" && bash "$T/scripts/review.sh" --preview "$repo" f.txt 2>&1 | head -3); case "$out" in *f.txt*) echo "PASS review preview";; *) echo "FAIL review preview: $out";; esac
out=$(bash "$T/scripts/review.sh" --preview "$repo" g.txt 2>&1 | head -3); case "$out" in *new*) echo "PASS review new file";; *) echo "FAIL review new file: $out";; esac
printf 'hello from helix\n' | WB_HERDR_SESSION=wbtest HERDR_ENV=1 HERDR_WORKSPACE_ID="$ws" bash "$T/scripts/agent-send.sh" 2>&1 | sed 's/^/   agent-send: /'
sleep 1; case "$(H pane read "$pane" --source visible 2>/dev/null)" in *"hello from helix"*) echo "PASS agent-send text reached the pane" ;; *) echo "FAIL agent-send text not in pane" ;; esac
[ -f "$HOME/.claude/skills/herdr/SKILL.md" ] && echo "PASS claude skill present" || echo "INFO claude skill absent (claude not installed here)"
H server stop >/dev/null 2>&1; echo "finished"
