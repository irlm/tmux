"""Regression tests run tools with temporary data, command doubles, and sockets."""
import concurrent.futures
import csv
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[1]
# These tests describe the tmux side. Running them from a Herdr pane must not
# make the scripts believe they were started by Herdr.
os.environ.pop('HERDR_ENV', None)
BASH = '/bin/bash'


def module(name):
    spec = importlib.util.spec_from_file_location(name, REPO / 'scripts' / (name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='tmux-test-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name).resolve()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f'{self.bin}:' + os.environ['PATH'],
                        TMUX_CONFIG_DIR=str(REPO), TMUX_DATA_DIR=str(self.root / 'data'),
                        TMUX_CACHE_DIR=str(self.root / 'cache'), TMUX=str(self.root / 'socket') + ',1,0',
                        TMUX_LOCAL_CONF=str(self.root / 'local.conf'), TMUX_THEME_DIR=str(self.root / 'theme'))

    def executable(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)
        return path

    def run_script(self, name, *args, input='', check=False):
        return subprocess.run([BASH, str(REPO / name), *args], env=self.env, input=input,
                              text=True, capture_output=True, timeout=20, check=check)

    def test_duplicate_note_preserves_original(self):
        notes = self.root / 'data/notes'
        notes.mkdir(parents=True)
        note = notes / 'planning.md'
        note.write_text('# Original\nKeep this.\n')
        self.executable('fzf', "cat >/dev/null; printf '\\nnew\\t+ New note\\n'")
        editor = self.executable('editor', 'exit 0')
        self.env['EDITOR'] = str(editor)
        result = self.run_script('scripts/notes.sh', input='planning\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(note.read_text(), '# Original\nKeep this.\n')

    def test_cancel_notes_creates_no_note(self):
        self.executable('fzf', 'cat >/dev/null; exit 130')
        result = self.run_script('scripts/notes.sh')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(list((self.root / 'data/notes').glob('*.md')), [])

    def test_note_with_spaces_is_opened_as_one_filename(self):
        notes = self.root / 'data/notes'; notes.mkdir(parents=True)
        note = notes / 'a note.md'; note.write_text('text\n')
        self.executable('fzf', "cat >/dev/null; printf '\\na note.md\\ta note | text\\n'")
        editor = self.executable('editor', 'printf "%s\\n" "$@" > "$TMUX_DATA_DIR/editor-args"')
        self.env['EDITOR'] = str(editor)
        result = self.run_script('scripts/notes.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'data/editor-args').read_text().splitlines(), [str(note)])

    def clone(self, dest, fail=False):
        self.env['CLONE_FAIL'] = '1' if fail else '0'
        self.executable('git', '''if [ "$1" = clone ]; then
    [ "$CLONE_FAIL" = 0 ] || exit 1
    mkdir -p "$3/.git"; printf 'new config' > "$3/managed"; exit 0
fi
exit 1''')
        return subprocess.run([BASH, '-c', 'source "$1"; clone_config tmux "$2"', 'test',
                               str(REPO / 'scripts/install-lib.sh'), str(dest)], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_failed_clone_leaves_custom_config_in_place(self):
        dest = self.root / 'config'; dest.mkdir(); (dest / 'personal').write_text('keep')
        result = self.clone(dest, fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((dest / 'personal').read_text(), 'keep')
        self.assertEqual(list(self.root.glob('config.backup.*')), [])

    def test_successful_clone_preserves_custom_config_in_backup(self):
        dest = self.root / 'config'; dest.mkdir(); (dest / 'personal').write_text('keep')
        result = self.clone(dest)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((dest / 'managed').is_file())
        backups = list(self.root.glob('config.backup.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'personal').read_text(), 'keep')

    def test_custom_origin_containing_username_is_not_managed(self):
        result = subprocess.run([BASH, '-c', 'source "$1"; managed_remote "$2" tmux', 'test',
                                 str(REPO / 'scripts/install-lib.sh'),
                                 'https://example.com/not-irlm/tmux.git'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_personal_rc_include_preserves_content_and_is_idempotent(self):
        rc = self.root / '.bash_profile'
        rc.write_text('export PERSONAL_SETTING=keep\n')
        for _ in range(2):
            result = subprocess.run([BASH, '-c', 'source "$1"; append_shell_include "$2" bash',
                                     'test', str(REPO / 'scripts/install-lib.sh'), str(rc)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(rc.read_text().startswith('export PERSONAL_SETTING=keep\n'))
        self.assertEqual(rc.read_text().count('# tmux environment'), 1)
        backups = list(self.root.glob('.bash_profile.backup.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), 'export PERSONAL_SETTING=keep\n')

    def test_generated_shell_integration_runs_for_each_shell(self):
        self.executable('oh-my-posh', 'printf "%s\\n" "$*" >> "$TEST_CALLS"')
        self.executable('zoxide', 'printf "%s\\n" "$*" >> "$TEST_CALLS"')
        self.env['TEST_CALLS'] = str(self.root / 'calls')
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                if not shutil.which(shell): continue
                output = self.root / f'generated.{shell}'
                subprocess.run([BASH, '-c', 'source "$1"; write_shell_integration "$2" desktop "$3"',
                                'test', str(REPO / 'scripts/install-lib.sh'), shell, str(output)], check=True)
                result = subprocess.run([shell, '-c', '. "$1"', 'test', str(output)], env=self.env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = Path(self.env['TEST_CALLS']).read_text()
                self.assertIn('init ' + shell, calls)

    def test_live_sessions_and_worktrees_are_selectable(self):
        projects = self.root / 'projects'; (projects / 'worktree').mkdir(parents=True)
        (projects / 'worktree/.git').write_text('gitdir: somewhere')
        self.env['TMUX_PROJECT_ROOTS'] = str(projects)
        listing = self.root / 'choices'; self.env['TEST_CHOICES'] = str(listing)
        self.executable('tmux', "if [ \"$1\" = list-sessions ]; then printf '$9\\tlive-work\\n'; fi")
        self.executable('fzf', 'cat > "$TEST_CHOICES"; exit 130')
        result = self.run_script('scripts/sessionizer.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        choices = listing.read_text()
        self.assertIn('session\t$9\tSession: live-work', choices)
        self.assertIn(str(projects / 'worktree'), choices)

    def test_matching_basenames_create_distinct_sessions(self):
        paths = [self.root / 'team-a/api', self.root / 'team-b/api']
        self.env['TMUX_PROJECT_ROOTS'] = str(self.root)
        self.env['TEST_CALLS'] = str(self.root / 'calls')
        self.executable('fzf', 'cat >/dev/null; printf "project\\t%s\\tProject\\n" "$TEST_SELECTED"')
        self.executable('tmux', '''printf '%s\\n' "$*" >> "$TEST_CALLS"
case "$1" in list-sessions) exit 0 ;; has-session) exit 1 ;; new-session) printf '$3\\n' ;; esac''')
        for path in paths:
            path.mkdir(parents=True)
            self.env['TEST_SELECTED'] = str(path)
            result = self.run_script('scripts/sessionizer.sh')
            self.assertEqual(result.returncode, 0, result.stderr)
        created = [line for line in (self.root / 'calls').read_text().splitlines() if line.startswith('new-session')]
        self.assertEqual(len(created), 2)
        names = [line.split(' -s ')[1].split(' -c ')[0] for line in created]
        self.assertNotEqual(names[0], names[1])
        self.assertEqual((self.root / 'data/recent-projects').read_text().splitlines(),
                         [str(paths[1]), str(paths[0])])

    def test_ai_error_is_visible_and_literal_query_reaches_provider(self):
        calls = self.root / 'question'; self.env['TEST_QUESTION'] = str(calls)
        self.env['TMUX_AI_COMMAND'] = str(self.executable('provider',
            'printf "%s" "$1" > "$TEST_QUESTION"; echo "authentication failed" >&2; exit 42'))
        query = "what's wrong; $(touch NEVER) \"quotes\"\nline two"
        result = self.run_script('scripts/ai-ask.sh', query, input='\n')
        self.assertEqual(result.returncode, 42)
        self.assertIn('authentication failed', result.stdout)
        self.assertIn('Press Enter', result.stdout)
        self.assertEqual(calls.read_text(), query)
        self.assertFalse((REPO / 'NEVER').exists())

    def test_ai_success_is_paged(self):
        self.env['TMUX_AI_COMMAND'] = str(self.executable('provider', 'printf "long answer\\n"'))
        self.executable('less', 'cat "${@: -1}"')
        result = self.run_script('scripts/ai-ask.sh', 'question')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('long answer', result.stdout)

    def test_search_scope_and_html_results(self):
        search = module('websearch_fetch')
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b'''<a class="result-link" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fgithub.com%2Fone">Same <b>title</b></a><a href="https://github.com/two" class='result-link'>Same title</a>'''
        output = io.StringIO()
        with mock.patch.object(search.urllib.request, 'urlopen', return_value=response) as request, mock.patch('sys.stdout', output):
            self.assertEqual(search.main(['tmux', '--site', 'github']), 0)
        self.assertIn('site%3Agithub.com', request.call_args.args[0].full_url)
        rows = [line.split('\t') for line in output.getvalue().splitlines()]
        self.assertEqual(rows, [['https://github.com/one', 'Same title'], ['https://github.com/two', 'Same title']])

    def test_search_failure_has_browser_fallback(self):
        search = module('websearch_fetch')
        output = io.StringIO()
        with mock.patch.object(search.urllib.request, 'urlopen', side_effect=OSError('offline')), mock.patch('sys.stdout', output), mock.patch('sys.stderr', io.StringIO()):
            self.assertEqual(search.main(['some question']), 0)
        self.assertTrue(output.getvalue().startswith('https://duckduckgo.com/?q=some+question\t'))

    def test_same_title_selection_uses_its_own_url(self):
        self.env['TEST_OPENED'] = str(self.root / 'opened')
        self.executable('python3', "printf 'https://example.com/one\\tSame title\\nhttps://example.com/two\\tSame title\\n'")
        self.executable('fzf', "cat >/dev/null; printf '\\nhttps://example.com/two\\tSame title\\n'")
        self.executable('w3m', 'printf "%s" "$1" > "$TEST_OPENED"')
        self.env['SSH_CONNECTION'] = 'test'; self.env.pop('DISPLAY', None); self.env.pop('WAYLAND_DISPLAY', None)
        result = self.run_script('scripts/websearch.sh', "literal ' question")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'opened').read_text(), 'https://example.com/two')

    def test_ssh_snapshot_parsing_handles_absolute_paths_and_ports(self):
        ssh = module('ssh_info')
        snapshot = '10 1 bash\n20 10 /bin/bash ssh-remote.sh\n30 20 /usr/bin/ssh -o ControlMaster=auto -p 2222 alice@server tmux\n'
        self.assertIn('server#[default] as alice:2222', ssh.find_remote(10, snapshot))
        self.assertEqual(ssh.destination('sleep 10'), '')

    def test_network_cache_rejects_corruption_and_is_atomic(self):
        cache = self.root / 'cache'; cache.mkdir()
        (cache / 'network').write_text('$(touch NEVER) corrupt data')
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.run_script('scripts/net_speed.sh'), range(8)))
        self.assertTrue(all(r.returncode == 0 for r in results), [r.stderr for r in results])
        fields = (cache / 'network').read_text().split()
        self.assertEqual(len(fields), 5)
        self.assertTrue(all(field.isdigit() for field in fields))
        self.assertEqual(cache.stat().st_mode & 0o777, 0o700)

    def test_help_pager_hands_over_to_the_palette_on_f(self):
        # 40x120 needs paging; 62x238 (an 85% popup on a 280x73 client) fits
        # on one screen, where a pager without its terminal on stderr used to
        # sit in "Waiting for data".
        for rows, cols in ((40, 120), (62, 238)):
            with self.subTest(size=(rows, cols)):
                self.help_hands_over(rows, cols)

    def help_hands_over(self, rows, cols):
        import fcntl, pty, select, struct, termios, time
        self.env['TEST_PALETTE'] = str(self.root / f'palette-{rows}')
        self.executable('fzf', 'cat > "$TEST_PALETTE"; exit 130')
        pid, fd = pty.fork()
        if pid == 0:  # pragma: no cover - child
            os.execve(BASH, [BASH, str(REPO / 'scripts/actions.sh'), 'run', 'help'],
                      dict(self.env, TERM='xterm-256color'))
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
        screen = b''
        deadline = time.monotonic() + 10
        while b'q: close' not in screen.split(b'TMUX SHORTCUTS')[-1] and time.monotonic() < deadline:
            if select.select([fd], [], [], 0.2)[0]:
                screen += os.read(fd, 65536)
        time.sleep(0.5)
        while select.select([fd], [], [], 0.1)[0]:
            screen += os.read(fd, 65536)
        self.assertIn(b'F: search commands', screen)
        self.assertIn(b'Help | F: search commands | Space/b: page | /: search | q: close', screen)
        self.assertNotIn(b'Waiting for data', screen)
        os.write(fd, b'F')
        while time.monotonic() < deadline:
            if select.select([fd], [], [], 0.2)[0]:
                try:
                    screen += os.read(fd, 65536)
                except OSError:
                    break
            if os.waitpid(pid, os.WNOHANG)[0]:
                break
        else:
            os.kill(pid, 9)
            self.fail('help did not exit after F:\n' + screen.decode(errors='replace')[-800:])
        os.close(fd)
        self.assertNotIn(b'Waiting for data', screen)
        self.assertNotIn(b'Terminated', screen)
        self.assertIn('Search commands', Path(self.env['TEST_PALETTE']).read_text())

    def test_compact_status_skips_collectors(self):
        result = self.run_script('scripts/status_right.sh', '80')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertFalse((self.root / 'cache').exists())

    def test_special_day_action_replays_the_selected_art(self):
        listing = self.root / 'celebrations'
        self.env['TEST_CELEBRATIONS'] = str(listing)
        self.executable('fzf', 'cat > "$TEST_CELEBRATIONS"; printf "halloween\\tHappy Halloween!\\n"')
        result = self.run_script('scripts/actions.sh', 'run', 'special-days')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Happy Halloween!', result.stdout)
        self.assertIn('\\_/', result.stdout)
        self.assertIn('july-4\tHappy 4th of July!', listing.read_text())
        self.assertFalse((self.root / 'data/special-days').exists())

    def test_canceling_special_day_picker_is_quiet(self):
        self.executable('fzf', 'cat >/dev/null; exit 130')
        result = self.run_script('scripts/actions.sh', 'run', 'special-days')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '')

    def test_special_day_picker_keeps_the_preview_date(self):
        import sys
        self.executable('fzf', 'cat >/dev/null; printf "new-years-eve\\tNew Year\\n"')
        result = subprocess.run([sys.executable, str(REPO / 'scripts/special_days.py'),
                                 '--pick', '--date', '2030-12-31'], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("New Year's Eve! 2031", result.stdout)

    def test_special_day_auto_passes_the_date_to_the_greeting(self):
        import sys
        self.env['TEST_GREETING'] = str(self.root / 'greeting')
        self.executable('tmux', '''case "$1" in
    show-option) printf 'on\\n' ;;
    display-message) printf '80 24 0\\n' ;;
    display-popup)
        for greeting_argument in "$@"; do greeting_command=$greeting_argument; done
        bash -c "$greeting_command --plain" > "$TEST_GREETING"
        ;;
esac''')
        result = subprocess.run([sys.executable, str(REPO / 'scripts/special_days.py'),
                                 '--auto', '--client', '/dev/test', '--date', '2030-12-31'],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("New Year's Eve! 2031", Path(self.env['TEST_GREETING']).read_text())

    def test_special_day_status_updates_at_midnight_and_respects_opt_out(self):
        self.env.update(TEST_STATUS_TIME='1000', TEST_STATUS_DAY='2026-10-31', TEST_SPECIAL_DAYS='on')
        self.executable('date', '''if [ "$1" = '+%s %F' ]; then
    printf '%s %s\\n' "$TEST_STATUS_TIME" "$TEST_STATUS_DAY"
else exec /bin/date "$@"; fi''')
        self.executable('tmux', 'printf "off|nord||||||%s\\n" "$TEST_SPECIAL_DAYS"')
        self.executable('vm_stat', "printf 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\\nPages wired down: 10.\\nPages purgeable: 0.\\nAnonymous pages: 90.\\nPages occupied by compressor: 0.\\n'")
        self.executable('pmset', "echo 'No battery'")
        result = self.run_script('scripts/status_right.sh', '160')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('(^v^) Halloween', result.stdout)
        self.env['TEST_SPECIAL_DAYS'] = 'off'
        result = self.run_script('scripts/status_right.sh', '160')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('Halloween', result.stdout)
        self.env.update(TEST_SPECIAL_DAYS='on', TEST_STATUS_TIME='1001', TEST_STATUS_DAY='2026-11-01')
        result = self.run_script('scripts/status_right.sh', '160')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('Halloween', result.stdout)

    def test_special_day_auto_can_opt_out_and_retry_failed_popups(self):
        self.env.update(TEST_SPECIAL_DAYS='off', TEST_POPUP_FAIL='0')
        self.executable('tmux', '''case "$1" in
    show-option) printf '%s\\n' "$TEST_SPECIAL_DAYS" ;;
    display-message) printf '80 24 0\\n' ;;
    display-popup) [ "$TEST_POPUP_FAIL" = 0 ] ;;
esac''')
        import sys

        def greet():
            return subprocess.run([sys.executable, str(REPO / 'scripts/special_days.py'),
                                   '--auto', '--client', '/dev/test', '--date', '2026-07-04'],
                                  env=self.env, capture_output=True, text=True, timeout=10)

        result = greet()
        self.assertEqual(result.returncode, 0, result.stderr)
        stamps = self.root / 'data/special-days'
        self.assertFalse(stamps.exists())
        self.env.update(TEST_SPECIAL_DAYS='on', TEST_POPUP_FAIL='1')
        result = greet()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(stamps.iterdir()), [])
        self.env['TEST_POPUP_FAIL'] = '0'
        result = greet()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([stamp.name for stamp in stamps.iterdir()], ['2026-07-04'])

    def test_server_brew_requirements_cover_picker_and_search(self):
        calls = self.root / 'brew-calls'
        self.env['TEST_BREW'] = str(calls)
        self.executable('brew', 'printf "%s\\n" "$*" >> "$TEST_BREW"')
        result = subprocess.run([BASH, '-c',
            'source "$1"; command() { if [ "$1" = -v ]; then return 1; fi; builtin command "$@"; }; install_brew_tools server "$2"',
            'test', str(REPO / 'scripts/install-lib.sh'), str(REPO)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        installed = calls.read_text().splitlines()
        for formula in ('ripgrep', 'fd', 'jq', 'tlrc', 'python'):
            self.assertIn('install ' + formula, installed)
        self.assertNotIn('install lazydocker', installed)

    def test_remote_mode_unchanged_does_not_write_options(self):
        calls = self.root / 'tmux-writes'; self.env['TEST_WRITES'] = str(calls)
        self.executable('tmux', '''case "$1" in
    display-message) printf '$0\\n' ;;
    show) echo off ;;
    set|refresh-client) echo "$*" >> "$TEST_WRITES" ;;
esac''')
        result = self.run_script('scripts/remote-mode.sh', 'on', '$0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(calls.exists())

    def test_updater_reports_plugin_failure_and_quick_updates_neovim(self):
        installed = self.root / 'installed'; installed.mkdir()
        nvim = self.root / 'nvim'; (nvim / '.git').mkdir(parents=True); (nvim / 'init.lua').write_text('')
        (installed / '.git').mkdir(); shutil.copy(REPO / 'tools.tsv', installed / 'tools.tsv')
        (installed / 'tmux.conf').write_text("set -g @plugin 'tmux-plugins/tpm'\n")
        plugins = installed / 'plugins/tpm/bin'; plugins.mkdir(parents=True)
        (plugins.parent / 'tpm').write_text('#!/bin/sh\n'); (plugins.parent / 'tpm').chmod(0o755)
        for name in ('install_plugins', 'update_plugins', 'clean_plugins'):
            path = plugins / name; path.write_text('#!/bin/sh\necho simulated failure >&2\nexit 1\n'); path.chmod(0o755)
        for row in csv.DictReader(io.StringIO((REPO / 'tools.tsv').read_text()), delimiter='\t'):
            if row['command'] not in ('tmux', 'git', 'python3', 'curl'):
                self.executable(row['command'], 'exit 0')
        self.env.update(TMUX_CONFIG_DIR=str(installed), NVIM_CONFIG_DIR=str(nvim), TEST_NVIM=str(self.root / 'nvim-called'))
        self.executable('nvim', 'echo called > "$TEST_NVIM"')
        self.executable('git', '''if [ "$3" = remote ]; then
    case "$2" in */nvim) echo https://github.com/irlm/nvim.git ;; *) echo https://github.com/irlm/tmux.git ;; esac
fi
exit 0''')
        self.executable('tmux', 'if [ "$1" = -V ]; then echo "tmux 3.8"; elif [ "$1" = list-sessions ]; then exit 1; fi')
        self.executable('gh', 'echo dlvhdr/gh-dash')
        self.executable('infocmp', 'exit 0')
        result = self.run_script('update.sh', '--quick')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('tmux-install_plugins', result.stderr)
        self.assertIn('Update incomplete', result.stdout)
        self.assertNotIn('All up to date', result.stdout)
        self.assertTrue((self.root / 'nvim-called').exists())
        self.assertIn('simulated failure', (self.root / 'data/update-logs/tmux-install_plugins.log').read_text())

    def updater_git_fixture(self):
        real_git = shutil.which('git')
        self.env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1', GIT_TERMINAL_PROMPT='0')

        def git(directory, *args):
            return subprocess.run([real_git, '-C', str(directory), *args], env=self.env,
                                  capture_output=True, text=True, check=True, timeout=10).stdout

        installed = {}
        for name in ('tmux', 'nvim'):
            seed = self.root / ('seed-' + name); seed.mkdir()
            git(seed, 'init', '-b', 'main')
            git(seed, 'config', 'user.name', 'Update Test')
            git(seed, 'config', 'user.email', 'update@example.invalid')
            if name == 'tmux':
                (seed / '.gitignore').write_text('plugins/\n')
                (seed / 'tools.tsv').write_text('command\tbrew\tscoop\tprofile\n')
                (seed / 'tmux.conf').write_text('# isolated updater fixture\n')
            else:
                (seed / 'init.lua').write_text('return {}\n')
                (seed / 'lazy-lock.json').write_text('{"plugin": "old upstream"}\n')
            git(seed, 'add', '.')
            git(seed, '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'initial')
            remote = self.root / ('remote-' + name + '.git')
            git(self.root, 'clone', '--bare', str(seed), str(remote))
            checkout = self.root / name
            git(self.root, 'clone', str(remote), str(checkout))
            git(checkout, 'config', 'user.name', 'Update Test')
            git(checkout, 'config', 'user.email', 'update@example.invalid')
            installed[name] = checkout
            if name == 'nvim':
                (seed / 'lazy-lock.json').write_text('{"plugin": "new upstream"}\n')
                git(seed, 'add', 'lazy-lock.json')
                git(seed, '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'update lock')
                git(seed, 'push', str(remote), 'main')

        self.env.update(TMUX_CONFIG_DIR=str(installed['tmux']), NVIM_CONFIG_DIR=str(installed['nvim']),
                        TEST_NVIM=str(self.root / 'nvim-called'))
        plugins = installed['tmux'] / 'plugins/tpm/bin'; plugins.mkdir(parents=True)
        for path in [plugins.parent / 'tpm', *(plugins / name for name in ('install_plugins', 'update_plugins', 'clean_plugins'))]:
            path.write_text('#!/bin/sh\nexit 0\n'); path.chmod(0o755)
        self.executable('git', '''if [ "${TEST_FAIL_STASH:-0}" = 1 ] && [ "$3" = stash ]; then exit 1; fi
if [ "$3" = remote ] && [ "$4" = get-url ]; then
    case "$2" in */nvim) echo https://github.com/irlm/nvim.git ;; *) echo https://github.com/irlm/tmux.git ;; esac
else exec ''' + shlex_quote(real_git) + ''' "$@"; fi''')
        self.executable('tmux', 'if [ "$1" = -V ]; then echo "tmux 3.8"; elif [ "$1" = list-sessions ]; then exit 1; fi')
        self.executable('nvim', 'echo called > "$TEST_NVIM"')
        self.executable('gh', 'echo dlvhdr/gh-dash')
        self.executable('infocmp', 'exit 0')
        return installed['nvim'], git

    def test_updater_backs_up_generated_nvim_lock_before_pull(self):
        nvim, git = self.updater_git_fixture()
        generated = '{"plugin": "generated local"}\n'
        (nvim / 'lazy-lock.json').write_text(generated)
        result = self.run_script('update.sh', '--quick')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((nvim / 'lazy-lock.json').read_text(), '{"plugin": "new upstream"}\n')
        self.assertEqual(git(nvim, 'show', 'stash@{0}:lazy-lock.json'), generated)
        self.assertEqual(git(nvim, 'status', '--porcelain'), '')
        self.assertTrue((self.root / 'nvim-called').exists())

    def test_updater_preserves_staged_and_working_nvim_lock_versions(self):
        nvim, git = self.updater_git_fixture()
        staged = '{"plugin": "staged local"}\n'
        working = '{"plugin": "working local"}\n'
        (nvim / 'lazy-lock.json').write_text(staged)
        git(nvim, 'add', 'lazy-lock.json')
        (nvim / 'lazy-lock.json').write_text(working)
        result = self.run_script('update.sh', '--quick')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(git(nvim, 'show', 'stash@{0}:lazy-lock.json'), working)
        self.assertEqual(git(nvim, 'show', 'stash@{0}^2:lazy-lock.json'), staged)
        self.assertEqual((nvim / 'lazy-lock.json').read_text(), '{"plugin": "new upstream"}\n')

    def test_updater_keeps_custom_nvim_edits_under_normal_git_protection(self):
        nvim, git = self.updater_git_fixture()
        (nvim / 'lazy-lock.json').write_text('{"plugin": "local"}\n')
        (nvim / 'init.lua').write_text('return { custom = true }\n')
        result = self.run_script('update.sh', '--quick')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual((nvim / 'lazy-lock.json').read_text(), '{"plugin": "local"}\n')
        self.assertEqual((nvim / 'init.lua').read_text(), 'return { custom = true }\n')
        self.assertEqual(git(nvim, 'stash', 'list'), '')
        self.assertFalse((self.root / 'nvim-called').exists())

    def test_updater_stops_nvim_changes_if_lock_backup_fails(self):
        nvim, git = self.updater_git_fixture()
        original_head = git(nvim, 'rev-parse', 'HEAD')
        generated = '{"plugin": "generated local"}\n'
        (nvim / 'lazy-lock.json').write_text(generated)
        self.env['TEST_FAIL_STASH'] = '1'
        result = self.run_script('update.sh', '--quick')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('nvim lock backup', result.stderr)
        self.assertEqual((nvim / 'lazy-lock.json').read_text(), generated)
        self.assertEqual(git(nvim, 'rev-parse', 'HEAD'), original_head)
        self.assertEqual(git(nvim, 'stash', 'list'), '')
        self.assertFalse((self.root / 'nvim-called').exists())

    def test_updater_check_leaves_generated_nvim_lock_untouched(self):
        nvim, git = self.updater_git_fixture()
        generated = '{"plugin": "generated local"}\n'
        (nvim / 'lazy-lock.json').write_text(generated)
        result = self.run_script('update.sh', '--check')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((nvim / 'lazy-lock.json').read_text(), generated)
        self.assertEqual(git(nvim, 'stash', 'list'), '')


class TmuxIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('tmux'):
            raise unittest.SkipTest('tmux is not installed')
        cls.scratch = tempfile.TemporaryDirectory(prefix='tmux-integration-')
        cls.root = Path(cls.scratch.name).resolve()
        cls.socket = str(cls.root / 'socket')
        result = cls.tm('-f', '/dev/null', 'new-session', '-d', '-s', 'review', '/bin/sh')
        cls.tm('set-environment', '-g', 'TMUX_CONFIG_DIR', str(REPO))
        cls.tm('set-environment', '-g', 'TMUX_CACHE_DIR', str(cls.root / 'runtime-cache'))
        cls.tm('set-environment', '-g', 'TMUX_LOCAL_CONF', str(cls.root / 'none.conf'))
        cls.tm('set-environment', '-g', 'TMUX_THEME_DIR', str(cls.root / 'theme'))
        if result.returncode:
            cls.scratch.cleanup()
            raise RuntimeError('Cannot create isolated tmux socket: ' + result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.tm('kill-server')
        cls.scratch.cleanup()

    @classmethod
    def tm(cls, *args):
        return subprocess.run(['tmux', '-S', cls.socket, *args], capture_output=True, text=True, timeout=15)

    def test_config_parses(self):
        result = self.tm('source-file', '-n', str(REPO / 'tmux.conf'))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_full_config_loads_offline_and_generates_bindings(self):
        # This fixture relocates only the deployment root; execute the config.
        config = self.root / 'runtime.conf'
        config.write_text((REPO / 'tmux.conf').read_text().replace('~/.config/tmux', str(REPO)))
        result = self.tm('source-file', str(config))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('actions.sh', self.tm('list-keys', '-T', 'prefix', 'F').stdout)

    def test_help_renders_columns_in_a_real_terminal_and_scrolls(self):
        import sys
        import time
        command = shlex_quote(sys.executable) + ' ' + shlex_quote(str(REPO / 'scripts/help.py')) + ' | less -KR'
        result = self.tm('new-session', '-d', '-s', 'help-layout', '-x', '168', '-y', '46', command)
        self.assertEqual(result.returncode, 0, result.stderr)
        try:
            deadline = time.monotonic() + 5
            initial = ''
            while time.monotonic() < deadline:
                initial = self.tm('capture-pane', '-p', '-t', 'help-layout:').stdout
                if 'Attach or create tmux session' in initial:
                    break
                time.sleep(.05)
            self.assertIn('Tools & projects', initial)
            self.assertIn('Copy mode (no prefix)', initial)
            self.assertIn('Attach or create tmux session', initial)
            self.assertEqual(self.tm('display-message', '-p', '-t', 'help-layout:', '#{pane_width}x#{pane_height}').stdout.strip(), '168x46')
            self.tm('send-keys', '-t', 'help-layout:', 'G')
            deadline = time.monotonic() + 3
            bottom = initial
            while time.monotonic() < deadline:
                bottom = self.tm('capture-pane', '-p', '-t', 'help-layout:').stdout
                if bottom != initial and 'Git aliases' in bottom:
                    break
                time.sleep(.05)
            self.assertNotEqual(bottom, initial)
            self.assertIn('Git aliases', bottom)
        finally:
            self.tm('kill-session', '-t', 'help-layout')

    def test_lazygit_theme_is_loaded_by_the_real_application(self):
        import sys
        import time
        if not shutil.which('lazygit'):
            self.skipTest('lazygit is not installed')
        fixture = self.root / 'lazygit-repo'; fixture.mkdir()
        state = self.root / 'lazygit-state'; state.mkdir()
        theme = self.root / 'lazygit-theme'; theme.mkdir()
        (theme / 'theme').write_text('nord\n')
        base = self.root / 'lazygit-base.json'
        import json
        base.write_text(json.dumps({'git': {'autoFetch': False, 'autoRefresh': False,
            'autoDetectExternalChanges': False, 'autoForwardBranches': 'none'},
            'disableStartupPopups': True, 'update': {'method': 'never'}}))
        env = dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null', GIT_TERMINAL_PROMPT='0')
        subprocess.run(['git', '-C', str(fixture), 'init', '-q'], env=env, check=True)
        (fixture / 'example.txt').write_text('before\nkeep\n')
        subprocess.run(['git', '-C', str(fixture), 'add', 'example.txt'], env=env, check=True)
        subprocess.run(['git', '-C', str(fixture), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                        '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture'], env=env, check=True)
        (fixture / 'example.txt').write_text('after\nkeep\n')
        arguments = ['env', '-u', 'NO_COLOR', 'COLORTERM=truecolor', 'GIT_CONFIG_NOSYSTEM=1', 'GIT_CONFIG_GLOBAL=/dev/null',
                     'TMUX_THEME_DIR=' + str(theme), 'LG_CONFIG_FILE=' + str(base), sys.executable,
                     str(REPO / 'scripts/appearance.py'), 'lazygit', '--use-config-dir', str(state), '--path', str(fixture)]
        command = ' '.join(shlex_quote(value) for value in arguments)
        result = self.tm('new-session', '-d', '-s', 'lazygit-theme', '-x', '168', '-y', '46', command)
        self.assertEqual(result.returncode, 0, result.stderr)
        try:
            deadline = time.monotonic() + 8
            screen = ''
            while time.monotonic() < deadline:
                screen = self.tm('capture-pane', '-e', '-p', '-t', 'lazygit-theme:').stdout
                if 'example.txt' in screen and '38;2;242;161;168' in screen:
                    break
                time.sleep(.1)
            self.assertIn('example.txt', screen)
            self.assertIn('38;2;242;161;168', screen)
            self.assertIn('48;2;59;66;82', screen)
        finally:
            self.tm('kill-session', '-t', 'lazygit-theme')

    def test_theme_switch_is_saved_and_restored_on_the_isolated_server(self):
        import sys
        wrappers = self.root / 'theme-bin'; wrappers.mkdir(exist_ok=True)
        wrapper = wrappers / 'tmux'
        wrapper.write_text('#!/bin/sh\nexec ' + shlex_quote(shutil.which('tmux')) + ' -S ' + shlex_quote(self.socket) + ' "$@"\n')
        wrapper.chmod(0o755)
        directory = self.root / 'theme-switch'
        env = dict(os.environ, PATH=f'{wrappers}:' + os.environ['PATH'], TMUX_THEME_DIR=str(directory))
        for identifier, background in [('catppuccin', '#24273a'), ('contrast', '#20242e'), ('nord', '#2e3440')]:
            result = subprocess.run([sys.executable, str(REPO / 'scripts/appearance.py'), 'apply', identifier],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((directory / 'theme').read_text().strip(), identifier)
            self.assertIn(background, self.tm('show', '-gqv', 'popup-style').stdout)
            palette = self.tm('show-options', '-gqv', 'pane-colours[1]')
            if palette.returncode == 0:
                expected_red = {'nord': '#f2a1a8', 'catppuccin': '#ed8796', 'contrast': '#ffb4b4'}[identifier]
                self.assertIn(expected_red, palette.stdout)
        result = subprocess.run([sys.executable, str(REPO / 'scripts/appearance.py'), 'restore'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.tm('show', '-gqv', '@theme').stdout.strip(), 'nord')

    def test_path_quoting_preserves_shell_characters(self):
        import time
        literal = self.root / '$(printf EXPANDED)'; literal.mkdir(exist_ok=True)
        window = self.tm('new-window', '-d', '-P', '-F', '#{pane_id}', '-c', str(literal), '-n', 'literal', '/bin/sh')
        self.assertEqual(window.returncode, 0, window.stderr)
        pane = window.stdout.strip()
        try:
            # On Linux new-window can return before its child has changed directory.
            deadline = time.monotonic() + 3
            path = ''
            while time.monotonic() < deadline:
                path = self.tm('display-message', '-p', '-t', pane, '#{pane_current_path}').stdout.strip()
                if path == str(literal):
                    break
                time.sleep(.02)
            self.assertEqual(path, str(literal), 'new pane did not reach its requested directory')
            expression = self.tm('display-message', '-p', '-t', pane, 'cd #{q:pane_current_path} && pwd').stdout.strip()
            result = subprocess.run(['/bin/sh', '-c', expression], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(literal))
        finally:
            self.tm('kill-pane', '-t', pane)

    def test_ssh_status_is_scoped_to_session(self):
        self.tm('new-session', '-d', '-s', 'local', '/bin/sh')
        self.tm('set', '-g', 'status', 'on')
        pid = '12345'
        cache = self.root / 'cache'; cache.mkdir(exist_ok=True)
        import time
        (cache / ('ssh-' + pid)).write_text(f'{int(time.time())}\nSSH server\n')
        wrappers = self.root / 'bin'; wrappers.mkdir(exist_ok=True)
        wrapper = wrappers / 'tmux'
        real_tmux = shutil.which('tmux')
        wrapper.write_text('#!/bin/sh\nexec ' + shlex_quote(real_tmux) + ' -S ' + shlex_quote(self.socket) + ' "$@"\n')
        wrapper.chmod(0o755)
        session = self.tm('display-message', '-p', '-t', 'review', '#{session_id}').stdout.strip()
        env = dict(os.environ, PATH=f'{wrappers}:' + os.environ['PATH'], TMUX_CACHE_DIR=str(cache))
        result = subprocess.run([BASH, str(REPO / 'scripts/status_ssh.sh'), 'update', pid, session], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.tm('show', '-t', 'review', '-qv', 'status').stdout.strip(), '2')
        self.assertEqual(self.tm('show', '-A', '-t', 'local', '-qv', 'status').stdout.strip(), 'on')

    def test_runtime_bindings_and_local_overrides(self):
        self.tm('set', '-g', 'history-limit', '100000')
        self.tm('set', '-g', 'status-left-length', '60')
        self.tm('set', '-g', 'status-right-length', '140')
        wrappers = self.root / 'runtime-bin'; wrappers.mkdir(exist_ok=True)
        wrapper = wrappers / 'tmux'
        wrapper.write_text('#!/bin/sh\nexec ' + shlex_quote(shutil.which('tmux')) + ' -S ' + shlex_quote(self.socket) + ' "$@"\n')
        wrapper.chmod(0o755)
        override = self.root / 'local.conf'; override.write_text('set -g @profile compact\nset -g @history_limit 1234\nbind F display-message custom\n')
        env = dict(os.environ, PATH=f'{wrappers}:' + os.environ['PATH'], TMUX_CONFIG_DIR=str(REPO), TMUX_LOCAL_CONF=str(override), TMUX_THEME_DIR=str(self.root / 'theme'))
        result = subprocess.run([BASH, str(REPO / 'scripts/configure.sh')], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.tm('show', '-gqv', 'history-limit').stdout.strip(), '1234')
        binding = self.tm('list-keys', '-T', 'prefix', 'F').stdout
        self.assertIn('custom', binding)
        self.assertIn('actions.sh', self.tm('list-keys', '-T', 'prefix', 'g').stdout)


def shlex_quote(value):
    import shlex
    return shlex.quote(value)


if __name__ == '__main__':
    unittest.main()
