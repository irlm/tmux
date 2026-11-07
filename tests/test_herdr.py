"""The Herdr side: rendered config, plugin manifest, host-aware help, pickers.

Everything here runs without a Herdr server. A fake `herdr` on PATH records
what the scripts ask of it; the real binary, when installed, only validates
the rendered config and is never pointed at the user's session.
"""
import csv
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
BASH = '/bin/bash'
sys.path.insert(0, str(REPO / 'scripts'))
import help as help_layout  # noqa: E402
import llm_usage  # noqa: E402


class HerdrFixture(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='herdr-test-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name).resolve()
        self.bin = self.root / 'bin'; self.bin.mkdir()
        self.user = self.root / 'user'; self.user.mkdir()
        self.log = self.root / 'herdr-calls'
        env = {key: value for key, value in os.environ.items() if not key.startswith('HERDR') and key != 'TMUX'}
        self.env = dict(env, PATH=f'{self.bin}:' + env['PATH'], TMUX_CONFIG_DIR=str(REPO),
                        TMUX_DATA_DIR=str(self.root / 'data'), TMUX_CACHE_DIR=str(self.root / 'cache'),
                        TMUX_THEME_DIR=str(self.user), HERDR_ENV='1', HERDR_BIN_PATH=str(self.bin / 'herdr'),
                        HERDR_CONFIG_PATH=str(self.root / 'herdr' / 'config.toml'),
                        HELIX_CONFIG_HOME=str(self.root / 'helix'), NVIM_CONFIG_DIR=str(self.root / 'no-nvim'))

    def fake_herdr(self, body='exit 0'):
        path = self.bin / 'herdr'
        path.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> ' + str(self.log) + '\n' + body + '\n')
        path.chmod(0o755)
        return path

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def legacy_python(self):
        # A python3 whose pipes and files default to a legacy encoding, as on
        # Windows (cp1252 there). Shift JIS stands in where the system has
        # it: like cp1252, it has no character for the bytes of "◐".
        wrapper = self.bin / 'python3'
        wrapper.write_text(f'#!/bin/bash\nLC_ALL=ja_JP.SJIS exec {shlex.quote(sys.executable)} "$@"\n'); wrapper.chmod(0o755)
        bare = {key: value for key, value in self.env.items() if key not in ('PYTHONUTF8', 'PYTHONIOENCODING')}
        probe = subprocess.run([str(wrapper), '-c', 'import sys; print(sys.stdin.encoding)'], env=bare, input='', text=True, capture_output=True)
        if 'utf' in probe.stdout.lower() or probe.returncode != 0:
            self.skipTest('this system has no legacy locale to stand in for Windows')

    def run_script(self, name, *args, input='', env=None):
        return subprocess.run([BASH, str(REPO / name), *args], env=env or self.env, input=input,
                              text=True, capture_output=True, timeout=30)


class RenderTests(HerdrFixture):
    def rendered(self):
        self.fake_herdr()
        result = self.run_script('scripts/herdr-config.sh', '--print')
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_template_keys_and_registry_popups_are_rendered(self):
        text = self.rendered()
        self.assertIn('prefix = "ctrl+a"', text)
        self.assertIn('split_vertical = "prefix+|"', text)
        self.assertIn('key = "prefix+g"', text)
        self.assertIn('actions.sh run git', text)
        self.assertIn('key = "prefix+ctrl+u"', text)      # C-u -> ctrl chord
        self.assertIn('key = "prefix+shift+g"', text)     # G -> shift
        self.assertIn('status_right.sh --plain', text)
        self.assertNotIn('@@', text)

    def test_native_prompts_and_tmux_only_rows_are_not_popups(self):
        text = self.rendered()
        for native in ('new-session', 'rename-session', 'rename-window'):
            self.assertNotIn(f'run {native}"', text)
        with (REPO / 'actions.tsv').open() as stream:
            rows = list(csv.DictReader(stream, delimiter='\t'))
        for row in rows:
            if row['hosts'] == 'tmux':
                self.assertNotIn(f"run {row['id']}\"", text)
            elif row['id'] not in ('new-session', 'rename-session', 'rename-window'):
                self.assertIn(f"run {row['id']}\"", text)

    def test_theme_follows_the_saved_palette(self):
        (self.user / 'theme').write_text('catppuccin\n')
        text = self.rendered()
        self.assertIn('name = "catppuccin"', text)
        self.assertIn('overlay1 = "#cad3f5"', text)
        (self.user / 'theme').write_text('contrast\n')
        text = self.rendered()
        self.assertIn('name = "nord"', text)
        self.assertIn('overlay1 = "#f5f7fc"', text)

    def test_a_theme_picked_inside_herdr_is_kept_until_the_next_tmux_pick(self):
        self.fake_herdr()
        config = Path(self.env['HERDR_CONFIG_PATH']); config.parent.mkdir()
        config.write_text('onboarding = false\n# Generated by irlm/tmux earlier\n[theme]\nname = "gruvbox"\n')
        text = self.rendered()
        self.assertIn('name = "gruvbox"', text)
        self.assertIn('overlay1 = "#ebdbb2"', text)
        self.assertNotIn('text = ', text.split('[terminal]')[0])
        self.assertIn('herdr_theme=gruvbox', (self.user / 'options.env').read_text())
        # the picker in tmux forgets the Herdr pick and the palette mapping returns
        sys.path.insert(0, str(REPO / 'scripts'))
        import appearance
        appearance.apply_herdr(self.user, REPO)
        self.assertNotIn('herdr_theme', (self.user / 'options.env').read_text())
        config.write_text('# Generated by irlm/workbench earlier\n[theme]\nname = "nord"\n')
        self.assertIn('text = "#eceff4"', self.rendered())

    def theme_block(self, text):
        return text.split('[terminal]')[0]

    def test_a_palette_taken_from_a_herdr_theme_selects_that_theme_as_herdr_ships_it(self):
        themes = json.loads((REPO / 'themes.json').read_text())
        taken = {identifier: theme['herdr'] for identifier, theme in themes.items() if 'herdr' in theme}
        self.assertEqual(sorted(taken), ['dracula', 'gruvbox', 'kanagawa', 'one-dark', 'rose-pine',
                                         'solarized', 'tokyo-night', 'vesper'])
        for identifier, native in taken.items():
            with self.subTest(theme=identifier):
                (self.user / 'theme').write_text(identifier + '\n')
                block = self.theme_block(self.rendered())
                self.assertIn(f'name = "{native}"', block)     # a name the renderer knows
                self.assertIn('overlay1 = "#', block)
                self.assertNotIn('text = ', block)             # Herdr's own colours, not the palette's
        (self.user / 'theme').write_text('tokyo-night\n')
        self.assertIn('overlay1 = "#c0caf5"', self.rendered())

    def test_the_next_pick_replaces_the_previous_one_in_herdr(self):
        # Rendered files carry the name they were written with, so the theme
        # found installed is the previous pick, not one made in Herdr.
        config = Path(self.env['HERDR_CONFIG_PATH']); config.parent.mkdir()
        for previous, following, expected in (('catppuccin', 'nord', 'nord'), ('nord', 'gruvbox', 'gruvbox'),
                                              ('gruvbox', 'dracula', 'dracula'), ('dracula', 'catppuccin', 'catppuccin')):
            with self.subTest(previous=previous, following=following):
                (self.user / 'theme').write_text(previous + '\n')
                config.write_text(self.rendered())
                (self.user / 'theme').write_text(following + '\n')
                self.assertIn(f'name = "{expected}"', self.theme_block(self.rendered()))
                self.assertFalse((self.user / 'options.env').exists())

    def test_a_pick_in_herdr_is_noticed_against_the_name_written_last(self):
        config = Path(self.env['HERDR_CONFIG_PATH']); config.parent.mkdir()
        (self.user / 'theme').write_text('gruvbox\n')
        first = self.rendered()
        config.write_text(first.replace('name = "gruvbox"', 'name = "nord"'))   # Herdr's settings wrote nord
        block = self.theme_block(self.rendered())
        self.assertIn('name = "nord"', block)
        self.assertIn('overlay1 = "#eceff4"', block)
        self.assertNotIn('text = ', block)
        self.assertIn('herdr_theme=nord', (self.user / 'options.env').read_text())

    def test_a_pick_here_is_not_mistaken_for_one_made_in_herdr_on_an_older_file(self):
        # A file rendered before the written name was kept in it.
        config = Path(self.env['HERDR_CONFIG_PATH']); config.parent.mkdir()
        config.write_text('# Generated by irlm/workbench earlier\n[theme]\nname = "catppuccin"\n')
        (self.user / 'theme').write_text('tokyo-night\n')
        self.fake_herdr()
        result = self.run_script('scripts/herdr-config.sh', '--print', env=dict(self.env, WORKBENCH_THEME_PICK='1'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('name = "tokyo-night"', self.theme_block(result.stdout))
        self.assertFalse((self.user / 'options.env').exists())

    def test_status_entries_split_into_coloured_parts_on_request(self):
        text = self.rendered()
        self.assertEqual(text.count('status_right.sh --plain 160"'), 1)
        self.assertNotIn('--part', text)
        (self.user / 'options.env').write_text('herdr_status_colors=on\n')
        text = self.rendered()
        self.assertIn('--plain 160 --part cpu", interval_seconds = 5, timeout_seconds = 3, color = "#88c0d0"', text)
        self.assertIn('--part net", interval_seconds = 5, timeout_seconds = 3, color = "#d4a9ca"', text)
        self.assertIn('--part battery", interval_seconds = 5, timeout_seconds = 3, color = "#a3be8c"', text)

    def test_a_row_can_size_its_own_popup(self):
        text = self.rendered()
        self.assertIn('run info"\nwidth = 100\nheight = 36\n', text)
        self.assertIn('run git"\nwidth = "85%"\nheight = "85%"\n', text)

    def test_user_toml_and_popup_size_are_honoured(self):
        (self.user / 'herdr.toml').write_text('[theme.custom.light]\ntext = "#000000"\n')
        (self.user / 'options.env').write_text('popup_size=70%\n')
        text = self.rendered()
        self.assertIn('[theme.custom.light]', text)
        self.assertIn('width = "70%"', text)
        self.assertTrue(text.rstrip().endswith('text = "#000000"'))

    def test_plugin_manifest_lists_every_popup_as_a_pane(self):
        self.fake_herdr()
        result = self.run_script('scripts/herdr-config.sh', '--print-plugin')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('id = "irlm.workbench"', result.stdout)
        self.assertIn('[[panes]]\nid = "palette"', result.stdout)
        self.assertIn('"--entrypoint", "projects"', result.stdout)
        self.assertNotIn('id = "new-session"', result.stdout)

    def test_install_writes_config_and_links_plugin_through_the_cli(self):
        self.fake_herdr('case "$1 $2" in "config check") echo "config: ok";; "plugin list") echo "0 plugins";; esac')
        result = self.run_script('scripts/herdr-config.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        config = Path(self.env['HERDR_CONFIG_PATH'])
        self.assertTrue(config.read_text().startswith('# Generated by irlm/workbench'))
        self.assertTrue((self.user / 'herdr-plugin/herdr-plugin.toml').exists())
        self.assertIn(f'plugin link {self.user}/herdr-plugin', self.calls())

    def test_rejected_config_is_not_installed(self):
        self.fake_herdr('case "$1 $2" in "config check") echo "bad key"; exit 1;; esac')
        result = self.run_script('scripts/herdr-config.sh')
        self.assertEqual(result.returncode, 1)
        self.assertFalse(Path(self.env['HERDR_CONFIG_PATH']).exists())

    @unittest.skipUnless(shutil.which('herdr'), 'herdr is not installed')
    def test_real_herdr_accepts_the_rendered_config(self):
        env = dict(self.env, PATH=os.environ['PATH'])
        rendered = self.root / 'rendered.toml'
        rendered.write_text(subprocess.run([BASH, str(REPO / 'scripts/herdr-config.sh'), '--print'], env=env,
                                           capture_output=True, text=True, check=True).stdout)
        result = subprocess.run(['herdr', 'config', 'check'], env=dict(os.environ, HERDR_CONFIG_PATH=str(rendered)),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('issues found', result.stdout + result.stderr)


class ScriptTests(HerdrFixture):
    def test_navigation_sends_keys_to_an_editor_and_focuses_otherwise(self):
        self.fake_herdr('''case "$*" in
  *process-info*) echo '{"result":{"process_info":{"foreground_processes":[{"name":"'"$FRONT"'"}]}}}' ;;
  *) echo '{"result":{}}' ;;
esac''')
        env = dict(self.env, HERDR_ACTIVE_PANE_ID='w1:p2', FRONT='nvim')
        self.assertEqual(self.run_script('scripts/herdr-navigate.sh', 'left', env=env).returncode, 0)
        self.assertIn('pane send-keys w1:p2 ctrl+h', self.calls())
        env['FRONT'] = 'zsh'
        self.run_script('scripts/herdr-navigate.sh', 'down', env=env)
        self.assertIn('pane focus --direction down --pane w1:p2', self.calls())

    def test_picker_reads_the_pane_and_copies_the_choice(self):
        self.fake_herdr('''case "$*" in
  *"pane read"*) printf 'open https://example.org/a and ~/notes/todo.md at 4f3a2b1c\\n' ;;
esac''')
        (self.bin / 'fzf').write_text('#!/bin/bash\ncat | tail -1\n'); (self.bin / 'fzf').chmod(0o755)
        (self.bin / 'pbcopy').write_text('#!/bin/bash\ncat > "$TMUX_DATA_DIR/clip"\n'); (self.bin / 'pbcopy').chmod(0o755)
        (self.root / 'data').mkdir()
        env = dict(self.env, HERDR_ACTIVE_PANE_ID='w1:p1')
        result = self.run_script('scripts/pick.sh', 'hints', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('pane read w1:p1 --source recent-unwrapped --lines 2000', self.calls())
        self.assertEqual((self.root / 'data/clip').read_text(), '4f3a2b1c')

    def test_file_picker_opens_an_existing_file_at_its_line(self):
        target = self.root / 'src' / 'app.py'; target.parent.mkdir(); target.write_text('x = 1\n')
        self.fake_herdr('case "$*" in *"pane read"*) printf "see %s:12 then missing.py:3 and %s\\n" "$TARGET" "$TARGET" ;; esac')
        (self.bin / 'fzf').write_text('#!/bin/bash\ncat | head -1\n'); (self.bin / 'fzf').chmod(0o755)
        (self.bin / 'hx').write_text('#!/bin/bash\necho "hx $*" > "$TMUX_DATA_DIR/opened"\n'); (self.bin / 'hx').chmod(0o755)
        (self.root / 'data').mkdir()
        env = dict(self.env, HERDR_ACTIVE_PANE_ID='w1:p1', TARGET=str(target), EDITOR='hx')
        result = self.run_script('scripts/pick.sh', 'files', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'data/opened').read_text().strip(), f'hx {target}:12')

    def test_agent_send_types_into_the_agent_pane_of_this_workspace(self):
        self.fake_herdr('''case "$*" in
  *"agent list"*) echo '{"result":{"agents":[{"pane_id":"w2:p1","workspace_id":"w2"},{"pane_id":"w1:p3","workspace_id":"w1"}]}}' ;;
  *) echo '{"result":{}}' ;;
esac''')
        env = dict(self.env, HERDR_WORKSPACE_ID='w1')
        result = self.run_script('scripts/agent-send.sh', input='review this hunk\n', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        # one bracketed paste: a newline inside the text must not submit the prompt
        self.assertIn('pane send-text w1:p3 \x1b[200~review this hunk\x1b[201~', self.calls())
        self.assertFalse(any(call.startswith('pane send-text w2:p1') for call in self.calls()))

    def test_sessionizer_focuses_an_existing_workspace_and_creates_new_ones(self):
        project = self.root / 'projects/api'; (project / '.git').mkdir(parents=True)
        other = self.root / 'projects/web'; (other / '.git').mkdir(parents=True)
        self.fake_herdr('''case "$1 $2" in
  "api snapshot") printf '{"result":{"snapshot":{"workspaces":[{"workspace_id":"w1","label":"api"}],"panes":[{"workspace_id":"w1","cwd":"%s"}]}}}\\n' "$PROJECT" ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w2"}}}' ;;
  *) echo '{"result":{}}' ;;
esac''')
        (self.bin / 'fzf').write_text('#!/bin/bash\ngrep -F "$PICK" | head -1\n'); (self.bin / 'fzf').chmod(0o755)
        env = dict(self.env, PROJECT=str(project.resolve()), TMUX_PROJECT_ROOTS=str(self.root / 'projects'), PICK=str(project.resolve()))
        result = self.run_script('scripts/sessionizer.sh', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('workspace focus w1', self.calls())
        self.assertNotIn('workspace create', ' '.join(self.calls()))
        env['PICK'] = str(other.resolve())
        result = self.run_script('scripts/sessionizer.sh', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'workspace create --cwd {other.resolve()} --label web --no-focus', self.calls())
        self.assertIn('workspace focus w2', self.calls())
        self.assertIn(f'w2\t{other.resolve()}', (self.root / 'data/herdr-workspaces').read_text())


class RegistryTests(HerdrFixture):
    def test_palette_lists_every_row_for_the_host_despite_extra_columns_and_crlf(self):
        self.fake_herdr()
        result = self.run_script('scripts/actions.sh', 'list')
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = result.stdout.splitlines()
        self.assertIn('git', ' '.join(rows)); self.assertIn('pick', ' '.join(rows))
        self.assertGreater(len(rows), 20)
        crlf = self.root / 'registry'; crlf.mkdir()
        (crlf / 'actions.tsv').write_bytes((REPO / 'actions.tsv').read_bytes().replace(b'\n', b'\r\n'))
        (crlf / 'tools.tsv').write_bytes((REPO / 'tools.tsv').read_bytes())
        shutil.copytree(REPO / 'scripts', crlf / 'scripts')
        result = subprocess.run([BASH, str(crlf / 'scripts/actions.sh'), 'list'], env=dict(self.env, TMUX_CONFIG_DIR=str(crlf)),
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(len(result.stdout.splitlines()), len(rows))


    def test_herdr_wrapper_finds_the_binary_by_name_without_recursing(self):
        self.fake_herdr('echo "called with: $*"')
        env = {k: v for k, v in self.env.items() if k != 'HERDR_BIN_PATH'}
        result = subprocess.run([BASH, '-c', f'source {REPO}/scripts/lib.sh; herdr pane list; WB_HERDR_SESSION=t herdr agent list'],
                                env=env, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['called with: pane list', 'called with: --session t agent list'])


class HelpTests(unittest.TestCase):
    def test_help_lists_the_keys_of_the_host_it_runs_on(self):
        herdr = help_layout.render(120, host='herdr')
        tmux = help_layout.render(120, host='tmux')
        self.assertIn('HERDR SHORTCUTS', herdr)
        self.assertIn('Next / previous agent', herdr)
        self.assertNotIn('Next / previous agent', tmux)
        self.assertIn('Pick and copy text', herdr)
        self.assertIn('Restore sessions', tmux)
        self.assertNotIn('Restore sessions', herdr)
        self.assertIn('LLM usage and limits', herdr)
        self.assertIn('LLM usage and limits', tmux)
        for text in (herdr, tmux):
            self.assertIn('Helix (no prefix)', text)
            self.assertIn('Send selection or line to the agent', text)
            self.assertIn('Open a file:line from the pane', text)


class UsageTests(unittest.TestCase):
    def test_claude_transcripts_count_each_message_once(self):
        with tempfile.TemporaryDirectory() as scratch:
            file = Path(scratch) / 'session.jsonl'
            usage = {'input_tokens': 10, 'output_tokens': 5, 'cache_creation_input_tokens': 100, 'cache_read_input_tokens': 1000}
            line = json.dumps({'timestamp': '2026-11-03T12:00:00Z', 'message': {'role': 'assistant', 'id': 'm1', 'model': 'claude-opus-5-5', 'usage': usage}})
            file.write_text(line + '\n' + line + '\n' + json.dumps({'timestamp': '2026-11-03T13:00:00Z', 'message': {'role': 'assistant', 'id': 'm2', 'model': 'claude-fable-5-1', 'usage': usage}}) + '\n')
            parsed = llm_usage.parse_claude(file)
        self.assertEqual(sum(parsed['models'].values()), 2230)
        self.assertEqual(parsed['models']['claude-opus-5-5'], 1115)

    def test_antigravity_transcripts_count_model_steps_under_the_picked_model(self):
        with tempfile.TemporaryDirectory() as scratch:
            file = Path(scratch) / 'transcript.jsonl'
            file.write_text('\n'.join([
                json.dumps({'source': 'USER_EXPLICIT', 'type': 'USER_INPUT', 'created_at': '2026-11-03T10:00:00Z',
                            'content': 'The user changed setting `Model Selection` from None to Gemini 4 Argon (High). No need'}),
                json.dumps({'source': 'MODEL', 'type': 'PLANNER_RESPONSE', 'created_at': '2026-11-03T10:00:01Z',
                            'input_tokens': 7000, 'cache_read_tokens': 500, 'output_tokens': 170}),
                json.dumps({'source': 'MODEL', 'type': 'GENERIC', 'created_at': '2026-11-03T10:00:06Z', 'content': 'tool output'}),
            ]) + '\n')
            parsed = llm_usage.parse_antigravity(file)
        self.assertEqual(parsed['models'], {'Gemini 4 Argon': 7670})
        self.assertEqual(parsed['day_models']['2026-11-03'], {'Gemini 4 Argon': 7670})

    def test_since_reset_counts_only_the_current_weekly_window(self):
        totals = {'days': {'2026-10-20': 100, '2026-11-02': 10, '2026-11-04': 1},
                  'models': {'a': 111},
                  'day_models': {'2026-10-20': {'a': 100}, '2026-11-02': {'a': 10}, '2026-11-04': {'a': 1}}}
        rows = [('week', 4.0, '2026-11-10T17:00:00+00:00'), ('session', 0.0, '2026-11-04T19:00:00Z')]
        window = llm_usage.since_reset(rows, totals, 30)
        self.assertEqual(window['window_start'], '2026-11-03')
        self.assertEqual(window['window_total'], 1)
        self.assertEqual(llm_usage.since_reset([], totals, 30)['window_label'], '30 days')
        self.assertEqual(llm_usage.since_reset([], totals, 30)['window_total'], 111)

    def test_codex_transcripts_attribute_turns_to_the_current_model(self):
        with tempfile.TemporaryDirectory() as scratch:
            file = Path(scratch) / 'rollout.jsonl'
            file.write_text('\n'.join([
                json.dumps({'timestamp': '2026-11-03T12:00:00Z', 'type': 'turn_context', 'payload': {'model': 'gpt-6'}}),
                json.dumps({'timestamp': '2026-11-03T12:01:00Z', 'type': 'event_msg', 'payload': {'type': 'token_count', 'info': {'last_token_usage': {'total_tokens': 500}},
                            'rate_limits': {'primary': {'used_percent': 12.5, 'window_minutes': 300, 'resets_at': 1800000000}}}}),
            ]) + '\n')
            parsed = llm_usage.parse_codex(file)
        self.assertEqual(parsed['models'], {'gpt-6': 500})
        self.assertEqual(llm_usage.codex_windows(parsed['limits'])[0][:2], ('5h', 12.5))
        self.assertEqual(llm_usage.pretty_model('claude-opus-5-5'), 'Opus 5.5')
        self.assertEqual(llm_usage.pretty_model('gpt-6'), 'gpt-6')
        self.assertEqual(llm_usage.human(61_100_000), '61.1M')


if __name__ == '__main__':
    unittest.main()


class UsageCardTests(unittest.TestCase):
    def test_a_terminal_curses_cannot_draw_on_is_reported_not_raised(self):
        # The popup then shows the plain report (scripts/actions.sh, status 3).
        import curses
        from unittest import mock
        with mock.patch.object(llm_usage, 'gather', return_value=([], {})):
            with mock.patch('curses.wrapper', side_effect=curses.error('no colours here')):
                self.assertFalse(llm_usage.interactive(30, {}))
            with mock.patch('curses.wrapper', return_value=None):
                self.assertTrue(llm_usage.interactive(30, {}))
        self.assertEqual(llm_usage.SCREEN_FAILED, 3)


class AgentWorkbenchTests(HerdrFixture):
    """C-a w, C-a C-d, C-a C-g and the event hook behind the sidebar token."""

    def git_repo(self, name='repo'):
        repo = self.root / name; repo.mkdir()
        git = ['git', '-C', str(repo), '-c', 'user.email=t@t', '-c', 'user.name=t']
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        (repo / 'f.txt').write_text('a\nb\n')
        subprocess.run([*git, 'add', 'f.txt'], check=True)
        subprocess.run([*git, 'commit', '-q', '-m', 'one'], check=True)
        (repo / 'f.txt').write_text('a\nc\nd\n')
        (repo / 'g.txt').write_text('new\n')
        return repo

    def fake_fzf(self, body):
        (self.bin / 'fzf').write_text('#!/bin/bash\n' + body + '\n'); (self.bin / 'fzf').chmod(0o755)

    def test_rendered_config_queues_agents_and_shows_the_changes_token(self):
        self.fake_herdr()
        (self.user / 'options.env').write_text('worktree_dir=~/Projects/worktrees\n')
        rendered = self.run_script('scripts/herdr-config.sh', '--print').stdout
        self.assertIn('agent_panel_sort = "priority"', rendered)
        self.assertIn('show_agent_labels_on_pane_borders = true', rendered)
        self.assertIn('["$changes"]', rendered)
        self.assertIn('["agent", "$ctx", { token = "$ctx_big", fg = "#ebcb8b", bold = true }]', rendered)
        self.assertIn('claude = [["state_icon", "machine", "workspace", "tab"], ["terminal_title_stripped"], ["agent", "$ctx", {', rendered)
        self.assertIn('directory = "~/Projects/worktrees"', rendered)
        self.assertIn('key = "prefix+ctrl+d"', rendered)
        (self.user / 'options.env').write_text('herdr_agent_sort=spaces\n')
        self.assertIn('agent_panel_sort = "spaces"', self.run_script('scripts/herdr-config.sh', '--print').stdout)
        manifest = self.run_script('scripts/herdr-config.sh', '--print-plugin').stdout
        self.assertIn('[[events]]\non = "pane.agent_status_changed"\ncommand = ["bash", "' + str(REPO / 'scripts/agent-events.sh') + '"]', manifest)

    def test_a_plugin_linked_from_elsewhere_is_relinked_here(self):
        self.fake_herdr('''case "$1 $2" in
  "config check") echo "config: ok" ;;
  "plugin list") echo '{"result":{"plugins":[{"plugin_id":"irlm.workbench","plugin_root":"/tmp/stale/herdr-plugin"}]}}' ;;
esac''')
        result = self.run_script('scripts/herdr-config.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('plugin unlink irlm.workbench', self.calls())
        self.assertIn(f'plugin link {self.user}/herdr-plugin', self.calls())
        self.assertIn('was linked from /tmp/stale/herdr-plugin', result.stdout)

    def test_agents_picker_lists_by_urgency_and_focuses_the_pick(self):
        self.fake_herdr('''case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","agent":"claude","agent_status":"working","cwd":"/x","terminal_title_stripped":"Fix tests"},{"pane_id":"w2:p3","workspace_id":"w2","tab_id":"w2:t2","agent":"codex","agent_status":"blocked","cwd":"/y"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"api"},{"workspace_id":"w2","label":"web"}]}}' ;;
  *) echo '{"result":{}}' ;;
esac''')
        env = dict(self.env, HERDR_WORKSPACE_ID='w1')
        listed = self.run_script('scripts/agents.sh', '--list', env=env)
        self.assertEqual(listed.returncode, 0, listed.stderr)
        rows = listed.stdout.splitlines()
        self.assertTrue(rows[0].startswith('herdr\tw2:p3\t▲ blocked'), rows)   # blocked first
        self.assertIn('web/t2\tcodex', rows[0])
        self.assertIn('Fix tests', rows[1])
        self.fake_fzf('cat | head -1')
        result = self.run_script('scripts/agents.sh', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('agent focus w2:p3', self.calls())

    def test_tmux_keeps_its_own_w_and_the_agents_picker_is_bound_under_herdr_only(self):
        # Both can run on one desktop. C-a w in tmux is tmux's window tree, as
        # it was before the picker existed; the picker is Herdr's key.
        self.fake_herdr()
        tmux = self.bin / 'tmux'
        tmux.write_text('#!/bin/bash\nprintf "tmux %s\\n" "$*" >> ' + str(self.log) + '\n'); tmux.chmod(0o755)
        under_tmux = {key: value for key, value in self.env.items() if key != 'HERDR_ENV'}
        under_tmux['TMUX'] = '/tmp/tmux-1/default,1,0'
        bound = self.run_script('scripts/actions.sh', 'bind', env=under_tmux)
        self.assertEqual(bound.returncode, 0, bound.stderr)
        keys = [call.split()[2] for call in self.calls() if call.startswith('tmux bind-key ')]
        self.assertIn('C-d', keys)
        self.assertNotIn('w', keys)
        self.assertIn('bind w choose-tree -Zw', (REPO / 'tmux.conf').read_text())   # heals a running server on reload
        rendered = self.run_script('scripts/herdr-config.sh', '--print')
        self.assertIn('key = "prefix+w"', rendered.stdout)
        self.assertIn('actions.sh run agents', rendered.stdout)
        palette = self.run_script('scripts/actions.sh', 'list', env=under_tmux)
        self.assertNotIn('agents', palette.stdout)
        self.assertIn('agents', self.run_script('scripts/actions.sh', 'list').stdout)

    def test_agents_picker_shows_only_the_multiplexer_it_was_opened_in(self):
        # Both can run on one desktop. tmux's C-a w stays tmux's: its own panes,
        # no call into Herdr, and the other way round; Enter never jumps to a
        # window of the other multiplexer.
        self.fake_herdr('''case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","agent":"claude","agent_status":"working","cwd":"/x"}]}}' ;;
  *) echo '{"result":{}}' ;;
esac''')
        tmux = self.bin / 'tmux'
        tmux.write_text('#!/bin/bash\nprintf "tmux %s\\n" "$*" >> ' + str(self.log) + '\n'
                        'case "$1" in list-panes) printf "%%1\\tmain/0\\tclaude\\tFix tests\\t/x\\n" ;; esac\n')
        tmux.chmod(0o755)
        under_tmux = {key: value for key, value in self.env.items() if key != 'HERDR_ENV'}
        under_tmux['TMUX'] = '/tmp/tmux-1/default,1,0'
        listed = self.run_script('scripts/agents.sh', '--list', env=under_tmux)
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertEqual(listed.stdout.splitlines(), ['tmux\t%1\t? running \tmain/0\tclaude\t\tFix tests\t/x'])
        self.assertNotIn('agent list', self.calls())
        self.log.unlink()
        listed = self.run_script('scripts/agents.sh', '--list')   # under Herdr
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertEqual([row.split('\t')[0] for row in listed.stdout.splitlines()], ['herdr'])
        self.assertFalse([call for call in self.calls() if call.startswith('tmux ')], self.calls())

    def test_scripts_run_python_in_utf8_mode(self):
        # scripts/lib.sh for every script that sources it; the theme picker
        # does not, and sets it itself.
        env = {key: value for key, value in self.env.items() if key != 'PYTHONUTF8'}
        result = subprocess.run([BASH, '-c', 'source "$1"; python3 -c "import sys; print(sys.flags.utf8_mode)"', '_', str(REPO / 'scripts/lib.sh')],
                                env=env, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.stdout.strip(), '1', result.stderr)
        (self.bin / 'python3').write_text('#!/bin/bash\necho "utf8=${PYTHONUTF8:-}"\n'); (self.bin / 'python3').chmod(0o755)
        self.assertEqual(self.run_script('scripts/themes.sh', 'list', env=env).stdout.strip(), 'utf8=1')

    def test_pickers_read_and_write_utf8_where_python_defaults_to_a_legacy_encoding(self):
        # On Windows the agents picker could not print a state icon, and no
        # reader got past a pane title with Claude Code's spinner in it.
        self.legacy_python()
        project = self.root / 'projects/api'; (project / '.git').mkdir(parents=True)
        self.fake_herdr('''case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"pane_id":"w1:p3","workspace_id":"w1","tab_id":"w1:t1","agent":"claude","agent_status":"working","cwd":"/x","terminal_title":"◐ Port the report"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"café"}]}}' ;;
  "api snapshot") printf '{"result":{"snapshot":{"workspaces":[{"workspace_id":"w1","label":"café"}],"panes":[{"workspace_id":"w1","cwd":"%s","terminal_title":"◐ Port the report"}]}}}\\n' "$PROJECT" ;;
  *) echo '{"result":{}}' ;;
esac''')
        env = dict(self.env, HERDR_WORKSPACE_ID='w1', PROJECT=str(project.resolve()),
                   TMUX_PROJECT_ROOTS=str(self.root / 'projects'), PICK=str(project.resolve()))
        listed = self.run_script('scripts/agents.sh', '--list', env=env)
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertIn('w1:p3\t◐ working', listed.stdout)
        self.assertIn('café/t1\tclaude', listed.stdout)
        self.assertIn('◐ Port the report', listed.stdout)
        sent = self.run_script('scripts/agent-send.sh', input='review this hunk\n', env=env)
        self.assertEqual(sent.returncode, 0, sent.stderr)
        self.assertIn('pane send-text w1:p3 \x1b[200~review this hunk\x1b[201~', self.calls())
        (self.bin / 'fzf').write_text('#!/bin/bash\ngrep -F "$PICK" | head -1\n'); (self.bin / 'fzf').chmod(0o755)
        picked = self.run_script('scripts/sessionizer.sh', env=env)
        self.assertEqual(picked.returncode, 0, picked.stderr)
        self.assertIn('workspace focus w1', self.calls())
        probe = self.run_script('tests/windows-python-utf8.sh', env=env)
        self.assertEqual(probe.returncode, 0, probe.stdout + probe.stderr)
        self.assertIn('passed', probe.stdout)

    def test_review_opens_the_picked_file_at_its_first_changed_line(self):
        repo = self.git_repo()
        self.fake_herdr()
        self.fake_fzf('grep -F "f.txt" | head -1')
        (self.bin / 'hx').write_text('#!/bin/bash\necho "hx $PWD $*" > "$TMUX_DATA_DIR/opened"\n'); (self.bin / 'hx').chmod(0o755)
        (self.root / 'data').mkdir()
        # after the editor the list comes back; a second fzf run ends it
        self.fake_fzf('if [ -f "$TMUX_DATA_DIR/opened" ]; then exit 130; fi; grep -F "f.txt" | head -1')
        env = dict(self.env, EDITOR='hx', PATH=self.env['PATH'])
        result = self.run_script('scripts/review.sh', str(repo), env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'data/opened').read_text().strip(), f'hx {repo.resolve()} f.txt:2')
        preview = self.run_script('scripts/review.sh', '--preview', str(repo), 'g.txt', env=dict(env, PATH=self.env['PATH']))
        self.assertIn('new', preview.stdout)

    def test_agent_event_journals_the_change_and_reports_the_workspace_token(self):
        repo = self.git_repo()
        self.fake_herdr('case "$1 $2" in "pane get") printf \'{"result":{"pane":{"workspace_id":"w1","cwd":"%s"}}}\\n\' "$REPO" ;; esac')
        event = json.dumps({'type': 'pane.agent_status_changed', 'pane_id': 'w1:p2', 'agent': 'claude', 'agent_status': 'done'})
        env = dict(self.env, HERDR_PLUGIN_EVENT_JSON=event, REPO=str(repo))
        result = self.run_script('scripts/agent-events.sh', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('workspace report-metadata w1 --source workbench --token changes=2 files +2 -1', self.calls())
        journal = (self.root / 'data/agent-journal.tsv').read_text().splitlines()
        self.assertEqual(journal[-1].split('\t')[1:], ['w1', 'w1:p2', 'claude', 'done'])
        subprocess.run(['git', '-C', str(repo), 'checkout', '-q', 'f.txt']); (repo / 'g.txt').unlink()
        self.run_script('scripts/agent-events.sh', env=env)
        self.assertIn('workspace report-metadata w1 --source workbench --token changes=clean', self.calls())

    def test_worktree_popup_creates_a_branch_worktree_under_herdr(self):
        repo = self.git_repo()
        self.fake_herdr()
        self.fake_fzf('cat >/dev/null; printf "feature-x\\n\\n"; exit 1')   # a typed name, Enter, nothing picked
        result = self.run_script('scripts/worktree.sh', str(repo))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'worktree create --cwd {repo.resolve()} --branch feature-x --focus', self.calls())
        self.fake_fzf(f'cat >/dev/null; printf "\\n\\n{repo.resolve()}\\tmain x\\n"')   # the main checkout picked
        result = self.run_script('scripts/worktree.sh', str(repo), input='\n')
        self.assertIn('main checkout', result.stdout)

    def test_an_old_herdr_is_refused_with_the_update_hint(self):
        self.fake_herdr('case "$1" in --version) echo "herdr 0.8.3" ;; esac')
        result = self.run_script('scripts/herdr-config.sh', '--check')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Herdr 0.8.3 is older than 0.9.5', result.stderr)
        self.assertIn('herdr update', result.stderr)
        self.fake_herdr('case "$1 $2" in "--version ") echo "herdr 0.9.12" ;; "config check") echo "config: ok" ;; esac')
        self.assertEqual(self.run_script('scripts/herdr-config.sh', '--check').returncode, 0)

    def test_editor_key_splits_beside_the_pane_and_starts_helix_there(self):
        self.fake_herdr('''case "$1 $2" in
  "pane split") echo '{"result":{"pane":{"pane_id":"w1:p9"}}}' ;;
  "pane process-info") [ "$3" = --pane ] && [ "$4" = w1:p9 ] && echo '{"result":{"process_info":{"foreground_processes":[{"name":"zsh"}]}}}' ;;
  *) echo '{"result":{}}' ;;
esac''')
        (self.bin / 'hx').write_text('#!/bin/bash\n'); (self.bin / 'hx').chmod(0o755)
        env = dict(self.env, HERDR_ACTIVE_PANE_ID='w1:p2', EDITOR='hx')
        result = self.run_script('scripts/actions.sh', 'run', 'editor', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('pane split w1:p2 --direction right --focus', self.calls())
        self.assertIn('pane run w1:p9 hx .', self.calls())

    def test_editor_key_follows_the_machine_default_and_the_picker_sets_it(self):
        self.fake_herdr('''case "$1 $2" in
  "pane split") echo '{"result":{"pane":{"pane_id":"w1:p9"}}}' ;;
  "pane process-info") echo '{"result":{"process_info":{"foreground_processes":[{"name":"zsh"}]}}}' ;;
  *) echo '{"result":{}}' ;;
esac''')
        for name in ('hx', 'nvim'):
            (self.bin / name).write_text('#!/bin/bash\n'); (self.bin / name).chmod(0o755)
        (self.user / 'options.env').write_text('editor=nvim\n')
        env = dict(self.env, HERDR_ACTIVE_PANE_ID='w1:p2', EDITOR='hx')
        result = self.run_script('scripts/actions.sh', 'run', 'editor', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('pane run w1:p9 nvim .', self.calls())
        self.assertIn('key = "prefix+ctrl+v"', self.run_script('scripts/herdr-config.sh', '--print').stdout)
        self.fake_fzf("cat >/dev/null; printf '\\nhx\\t  Helix (hx)\\n'")   # Enter: this once
        result = self.run_script('scripts/editor.sh', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('pane run w1:p9 hx .', self.calls())
        self.assertEqual((self.user / 'options.env').read_text(), 'editor=nvim\n')
        self.fake_fzf("cat >/dev/null; printf 'ctrl-a\\nhx\\t  Helix (hx)\\n'")   # C-a: the default
        result = self.run_script('scripts/editor.sh', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.user / 'options.env').read_text(), 'editor=hx\n')
        self.assertEqual(self.run_script('scripts/editor.sh', '--default', env=env).stdout.strip(), 'hx')

    def test_filediff_stages_the_diff_of_a_tracked_or_new_file(self):
        repo = self.git_repo()
        env = dict(self.env, TMPDIR=str(self.root))
        for name, expect in (('f.txt', '+c'), ('g.txt', '+new'), ('[scratch]', 'No file')):
            self.assertEqual(subprocess.run([BASH, str(REPO / 'scripts/filediff.sh'), 'stage', name], cwd=repo, env=env).returncode, 0)
            shown = subprocess.run([BASH, str(REPO / 'scripts/filediff.sh'), 'show'], cwd=repo, env=env, capture_output=True, text=True).stdout
            self.assertIn(expect, shown, name)
        subprocess.run(['git', '-C', str(repo), 'checkout', '-q', 'f.txt'])
        subprocess.run([BASH, str(REPO / 'scripts/filediff.sh'), 'stage', 'f.txt'], cwd=repo, env=env)
        self.assertIn('no changes', subprocess.run([BASH, str(REPO / 'scripts/filediff.sh'), 'show'], cwd=repo, env=env, capture_output=True, text=True).stdout)

    def test_worktree_picker_can_start_a_fresh_agent_in_the_new_workspace(self):
        repo = self.git_repo()
        self.fake_herdr('''case "$1 $2" in
  "worktree create") echo '{"result":{"root_pane":{"pane_id":"w9:p1"},"workspace":{"workspace_id":"w9"}}}' ;;
  "pane process-info") echo '{"result":{"process_info":{"foreground_processes":[{"name":"zsh"}]}}}' ;;
  *) echo '{"result":{}}' ;;
esac''')
        self.fake_fzf('cat >/dev/null; printf "feature-y\\nctrl-a\\n"; exit 1')   # a typed name, then C-a
        result = self.run_script('scripts/worktree.sh', str(repo))
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn(f'worktree create --cwd {repo.resolve()} --branch feature-y --focus', self.calls())
        self.assertIn('pane run w9:p1 claude', self.calls())
        (self.user / 'options.env').write_text('worktree_agent=codex\n')
        self.run_script('scripts/worktree.sh', str(repo))
        self.assertIn('pane run w9:p1 codex', self.calls())

    def test_agent_event_reports_the_context_size_of_a_claude_pane(self):
        repo = self.git_repo()
        session = 'aaaaaaaa-1111-2222-3333-444444444444'
        transcript = self.root / 'claude/projects/-x-y' / f'{session}.jsonl'; transcript.parent.mkdir(parents=True)
        def turn(read, side=False):
            return json.dumps({'type': 'assistant', 'isSidechain': side, 'message': {'usage': {
                'input_tokens': 4, 'cache_read_input_tokens': read, 'cache_creation_input_tokens': 996, 'output_tokens': 50}}}) + '\n'
        transcript.write_text(turn(20000) + turn(999999, side=True) + turn(239000))   # a subagent's turn does not count
        self.fake_herdr('case "$1 $2" in "pane get") printf \'{"result":{"pane":{"workspace_id":"w1","agent":"claude","agent_session":{"value":"%s"},"cwd":"%s"}}}\\n\' "$SESSION" "$REPO" ;; esac')
        event = json.dumps({'type': 'pane.agent_status_changed', 'pane_id': 'w1:p2', 'agent_status': 'done'})
        env = dict(self.env, HERDR_PLUGIN_EVENT_JSON=event, REPO=str(repo), SESSION=session, CLAUDE_CONFIG_DIR=str(self.root / 'claude'))
        result = self.run_script('scripts/agent-events.sh', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('pane report-metadata w1:p2 --source workbench --token ctx_big=ctx 240k --clear-token ctx', self.calls())
        self.assertEqual((self.root / 'data/agent-journal.tsv').read_text().splitlines()[-1].split('\t')[1:], ['w1', 'w1:p2', 'claude', 'done'])
        (self.user / 'options.env').write_text('ctx_warn_k=500\n')
        self.run_script('scripts/agent-events.sh', env=env)
        self.assertIn('pane report-metadata w1:p2 --source workbench --token ctx=ctx 240k --clear-token ctx_big', self.calls())

    def test_context_size_survives_text_the_platform_cannot_decode(self):
        # Windows Python reads a pipe as cp1252, which has no character for
        # byte 0x9d (the end of a closing curly quote in UTF-8); and the tail
        # of a transcript can start inside a character on any platform.
        repo = self.git_repo()
        session = 'bbbbbbbb-1111-2222-3333-444444444444'
        transcript = self.root / 'claude/projects/-x-y' / f'{session}.jsonl'; transcript.parent.mkdir(parents=True)
        turn = json.dumps({'type': 'assistant', 'message': {'content': 'a “quoted” word', 'usage': {
            'input_tokens': 4, 'cache_read_input_tokens': 41000, 'cache_creation_input_tokens': 996}}}, ensure_ascii=False)
        transcript.write_bytes(b'\x9d the end of a cut character"}\n' + turn.encode('utf-8') + b'\n')
        self.fake_herdr('case "$1 $2" in "pane get") printf \'{"result":{"pane":{"workspace_id":"w1","agent":"claude","agent_session":{"value":"%s"},"cwd":"%s"}}}\\n\' "$SESSION" "$REPO" ;; esac')
        event = json.dumps({'type': 'pane.agent_status_changed', 'pane_id': 'w1:p2', 'agent_status': 'done'})
        for encoding in ('cp1252', 'utf-8'):
            with self.subTest(encoding=encoding):
                self.log.unlink(missing_ok=True)
                env = dict(self.env, HERDR_PLUGIN_EVENT_JSON=event, REPO=str(repo), SESSION=session,
                           CLAUDE_CONFIG_DIR=str(self.root / 'claude'), PYTHONIOENCODING=encoding)
                result = self.run_script('scripts/agent-events.sh', env=env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('pane report-metadata w1:p2 --source workbench --token ctx=ctx 42k --clear-token ctx_big', self.calls())

    def test_pane_lookup_survives_a_title_and_a_path_the_platform_cannot_decode(self):
        # Herdr answers in UTF-8 with the pane title in it. The first frame of
        # the spinner Claude Code puts there ends in byte 0x90, which cp1252
        # (what Windows Python reads a pipe as) has no character for; and a
        # path outside ASCII has to come back to the shell as UTF-8.
        repo = self.git_repo('café')
        session = 'cccccccc-1111-2222-3333-444444444444'
        transcript = self.root / 'claude/projects/-x-y' / f'{session}.jsonl'; transcript.parent.mkdir(parents=True)
        transcript.write_text(json.dumps({'type': 'assistant', 'message': {'usage': {'input_tokens': 4, 'cache_read_input_tokens': 41996}}}) + '\n')
        self.fake_herdr('case "$1 $2" in "pane get") printf \'{"result":{"pane":{"workspace_id":"w1","agent":"claude","terminal_title":"◐ Port the report","agent_session":{"value":"%s"},"cwd":"%s"}}}\\n\' "$SESSION" "$REPO" ;; esac')
        event = json.dumps({'type': 'pane.agent_status_changed', 'pane_id': 'w1:p2', 'agent_status': 'working', 'terminal_title': '◐ Port the report'}, ensure_ascii=False)
        for encoding in ('cp1252', 'utf-8'):
            with self.subTest(encoding=encoding):
                self.log.unlink(missing_ok=True)
                env = dict(self.env, HERDR_PLUGIN_EVENT_JSON=event, REPO=str(repo), SESSION=session,
                           CLAUDE_CONFIG_DIR=str(self.root / 'claude'), PYTHONIOENCODING=encoding)
                result = self.run_script('scripts/agent-events.sh', env=env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('workspace report-metadata w1 --source workbench --token changes=2 files +2 -1', self.calls())
                self.assertIn('pane report-metadata w1:p2 --source workbench --token ctx=ctx 42k --clear-token ctx_big', self.calls())

    def test_router_plugin_install_is_opt_in_and_goes_through_the_claude_cli(self):
        log = self.root / 'claude-calls'
        (self.bin / 'claude').write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> ' + str(log) + '\ncase "$*" in "plugin list") echo "none" ;; esac\n')
        (self.bin / 'claude').chmod(0o755)
        result = subprocess.run([BASH, '-c', f'source {REPO}/scripts/install-lib.sh; install_model_router'], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = log.read_text().splitlines()
        self.assertEqual(calls, ['plugin list', 'plugin marketplace add irlm/model-router', 'plugin install model-router@model-router --yes'])
        self.assertIn('restart Claude Code', result.stdout)
        (self.bin / 'claude').write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> ' + str(log) + '\ncase "$*" in "plugin list") echo "  model-router@model-router" ;; esac\n')
        log.unlink()
        result = subprocess.run([BASH, '-c', f'source {REPO}/scripts/install-lib.sh; install_model_router'], env=self.env, capture_output=True, text=True)
        self.assertEqual(log.read_text().splitlines(), ['plugin list'])
        self.assertIn('already installed', result.stdout)
