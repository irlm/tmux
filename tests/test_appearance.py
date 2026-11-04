"""Theme selection, contrast, config merging and literal tool arguments."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('appearance', ROOT / 'scripts/appearance.py')
appearance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appearance)


def luminance(color):
    components = [int(color[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    components = [value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4 for value in components]
    return sum(value * weight for value, weight in zip(components, (.2126, .7152, .0722)))


def contrast(first, second):
    low, high = sorted((luminance(first), luminance(second)))
    return (high + .05) / (low + .05)


class AppearanceTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='tmux-appearance-')
        self.addCleanup(self.scratch.cleanup)
        self.directory = Path(self.scratch.name) / 'theme'

    def test_text_and_status_colors_contrast_on_normal_and_selected_rows(self):
        for identifier, theme in appearance.catalog().items():
            colors = theme['colors']
            for surface in ('background', 'selection'):
                for role in ('foreground', 'muted', 'accent', 'blue', 'cyan', 'green', 'yellow', 'red', 'magenta'):
                    with self.subTest(theme=identifier, role=role, surface=surface):
                        self.assertGreaterEqual(contrast(colors[role], colors[surface]), 4.5)

    def test_lazygit_keeps_red_readable_on_selected_lines(self):
        nord = appearance.catalog()['nord']
        styles = appearance.lazygit_theme(nord)['gui']['theme']
        self.assertIn('bold', styles['unstagedChangesColor'])
        self.assertGreaterEqual(contrast(styles['unstagedChangesColor'][0], styles['selectedLineBgColor'][0]), 4.5)
        self.assertNotIn('git', appearance.lazygit_theme(nord))

    def test_lazygit_pages_diffs_through_delta_only_when_installed(self):
        with mock.patch.object(appearance.shutil, 'which', lambda name: '/usr/bin/delta' if name == 'delta' else None):
            self.assertIn('delta --dark --paging=never', appearance.lazygit_pager()['git']['paging']['pager'])
        with mock.patch.object(appearance.shutil, 'which', lambda name: None):
            self.assertEqual(appearance.lazygit_pager(), {})

    def test_selection_is_persisted_without_editing_repo_templates(self):
        original = (ROOT / 'catppuccin.omp.json').read_bytes()
        with mock.patch.object(appearance, 'apply_tmux') as apply:
            appearance.select_theme('catppuccin', directory=self.directory)
        self.assertEqual(appearance.current_theme(directory=self.directory)[0], 'catppuccin')
        self.assertEqual((ROOT / 'catppuccin.omp.json').read_bytes(), original)
        generated = json.loads((self.directory / 'lazygit.yml').read_text())
        self.assertEqual(generated['gui']['theme']['unstagedChangesColor'][0], '#ed8796')
        self.assertEqual(self.directory.stat().st_mode & 0o777, 0o700)
        self.assertTrue((self.directory / 'prompt.omp.json').is_file())
        apply.assert_called_once()

    def test_cancel_or_unknown_theme_does_not_create_outputs(self):
        with self.assertRaises(ValueError):
            appearance.select_theme('../unknown', directory=self.directory)
        self.assertFalse(self.directory.exists())

    def test_canceling_the_picker_keeps_the_current_theme(self):
        executable_dir = self.directory.parent / 'bin'
        executable_dir.mkdir()
        executable = executable_dir / 'fzf'
        executable.write_text('#!/bin/sh\ncat >/dev/null\nexit 130\n')
        executable.chmod(0o755)
        env = dict(os.environ, PATH=f'{executable_dir}:' + os.environ['PATH'], TMUX_THEME_DIR=str(self.directory))
        result = subprocess.run(['/bin/bash', str(ROOT / 'scripts/themes.sh')],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.directory.exists())

    def test_picker_saves_the_selected_palette(self):
        executable_dir = self.directory.parent / 'bin'
        executable_dir.mkdir()
        for name, body in {
            'fzf': 'cat >/dev/null\nprintf "catppuccin\\tCatppuccin Macchiato\\n"\n',
            'tmux': 'exit 1\n',
        }.items():
            executable = executable_dir / name
            executable.write_text('#!/bin/sh\n' + body)
            executable.chmod(0o755)
        env = dict(os.environ, PATH=f'{executable_dir}:' + os.environ['PATH'], TMUX_THEME_DIR=str(self.directory))
        result = subprocess.run(['/bin/bash', str(ROOT / 'scripts/themes.sh')],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.directory / 'theme').read_text(), 'catppuccin\n')
        self.assertTrue((self.directory / 'lazygit.yml').is_file())

    def test_fzf_preserves_non_color_options_without_accumulating_palettes(self):
        themes = appearance.catalog()
        existing = "--height=80% --bind='ctrl-x:abort' --color=fg:red"
        first = appearance.fzf_options(themes['nord'], existing)
        second = appearance.fzf_options(themes['catppuccin'], first)
        self.assertIn('--height=80%', second)
        self.assertIn('--bind=ctrl-x:abort', second)
        self.assertEqual(second.count('--color='), 1)
        self.assertIn('bg:#24273a', second)
        self.assertNotIn('fg:red', second)

    def test_git_color_environment_preserves_existing_configuration(self):
        original = {'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'custom.setting', 'GIT_CONFIG_VALUE_0': 'keep'}
        updated = appearance.git_color_environment(appearance.catalog()['nord'], original)
        self.assertEqual(updated['GIT_CONFIG_KEY_0'], 'custom.setting')
        self.assertEqual(updated['GIT_CONFIG_VALUE_0'], 'keep')
        self.assertEqual(updated['GIT_CONFIG_KEY_1'], 'color.diff.old')
        self.assertEqual(updated['GIT_CONFIG_VALUE_1'], '#f2a1a8')
        self.assertEqual(original['GIT_CONFIG_COUNT'], '1')

    def test_lazygit_overlay_is_appended_to_existing_custom_configuration(self):
        base = self.directory.parent / 'personal settings.yml'
        base.write_text('customCommands: []\n')
        configs = appearance.lazygit_config_files(str(base), self.directory).split(',')
        self.assertEqual(configs, [str(base), str(self.directory / 'lazygit.yml')])
        self.assertEqual(base.read_text(), 'customCommands: []\n')

    def test_lazygit_cli_arguments_and_custom_configs_remain_literal(self):
        self.directory.mkdir()
        personal = str(self.directory.parent / 'settings with spaces.yml')
        question = "path with ' quotes; $(literal)"
        with mock.patch.dict(os.environ, {'TMUX_THEME_DIR': str(self.directory)}, clear=False), \
             mock.patch.object(appearance.os, 'execvpe') as launch:
            appearance.launch_lazygit(['--use-config-file', personal, '--path', question])
        executable, arguments, environment = launch.call_args.args
        self.assertEqual(executable, 'lazygit')
        self.assertEqual(arguments, ['lazygit', '--path', question])
        self.assertEqual(environment['LG_CONFIG_FILE'], personal + ',' + str(self.directory / 'lazygit.yml'))

    def test_shell_theme_environment_preserves_lazygit_config_and_is_idempotent(self):
        theme = appearance.catalog()['nord']
        appearance.write_outputs(theme, self.directory)
        env = dict(os.environ, TMUX_THEME_DIR=str(self.directory),
                   LG_CONFIG_FILE='/tmp/personal.yml', FZF_DEFAULT_OPTS='--height=80%')
        command = '. "$1"; . "$1"; printf "%s\\n%s\\n" "$LG_CONFIG_FILE" "$FZF_DEFAULT_OPTS"'
        result = subprocess.run(['/bin/bash', '-c', command, 'test', str(ROOT / 'shell/theme-env.sh')],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], '/tmp/personal.yml,' + str(self.directory / 'lazygit.yml'))
        self.assertEqual(lines[1].count('--color='), 1)
        self.assertIn('--height=80%', lines[1])


if __name__ == '__main__':
    unittest.main()
