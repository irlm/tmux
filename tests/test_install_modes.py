"""What each install mode does, read from the installers themselves.

Not a run: a guard that the default stays the workbench, --server stays
light, --full carries everything, and the pieces every mode needs (Helix
config, Herdr, the workbench clone under its current name) are present.
"""
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def block(text, start, end):
    begin = text.index(start)
    stop = text.index(end, begin) if end else len(text)
    return text[begin:stop]


class InstallModeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.install = (REPO / 'install.sh').read_text()
        cls.setup = (REPO / 'setup.sh').read_text()
        cls.windows = (REPO / 'install.ps1').read_text(encoding='utf-8-sig')
        cls.server = block(cls.install, '# ─── Server (light) mode', '# ─── Default install mode')
        cls.default = block(cls.install, '# ─── Default install mode', None)

    def assert_each(self, text, needles, present=True, label=''):
        for needle in needles:
            with self.subTest(label=label, needle=needle):
                self.assertEqual(needle in text, present)

    def test_default_is_the_workbench_without_toolchains_or_docker(self):
        self.assert_each(self.default, [
            'install_brew_tools desktop', 'install_helix_linux', 'clone_config workbench',
            'install_helix_config', 'rm -f -- "$HOME/.config/tmux-user/profile"', 'install_tmux_plugins',
            'ensure_nerd_font', 'configure_terminal_font', 'install_shell_integration desktop',
            'install_herdr_workbench "$INSTALL_ASSETS" "$WANT_HERDR"', 'check_install_tools desktop',
            'gh extension install dlvhdr/gh-dash', 'install.sh --full'], label='default')
        self.assert_each(self.default, ['rustup', 'get.docker.com', '--cask docker', 'openjdk', 'golang', 'coursier', 'nodejs', 'metals'],
                         present=False, label='default')
        self.assertIn('--agent|-a)  MODE="default"', self.install)

    def test_server_stays_light_and_can_take_herdr(self):
        self.assert_each(self.server, [
            'install_helix_linux', 'install_brew_tools server', 'clone_config workbench', 'install_helix_config',
            "printf 'server\\n' > \"$HOME/.config/tmux-user/profile\"", 'install_tmux_plugins',
            'install_shell_integration server', 'install_herdr_workbench "$INSTALL_ASSETS" "$WANT_HERDR"',
            'check_install_tools server'], label='server')
        self.assert_each(self.server, ['rustup', 'get.docker.com', '--cask docker', 'openjdk', 'oh-my-posh', 'gh-dash', 'ensure_nerd_font'],
                         present=False, label='server')
        self.assertIn('[ "$MODE" = server ] && WANT_HERDR=0 || WANT_HERDR=1', self.install)

    def test_full_hands_over_to_setup_with_everything(self):
        self.assertIn('TMUX_WANT_NVIM="$WANT_NVIM" TMUX_WANT_HERDR="$WANT_HERDR" bash "$TMPSCRIPT"', self.install)
        self.assert_each(self.setup, [
            'clone_config workbench', 'install_helix_config', 'install_helix_linux', 'install_brew_tools desktop',
            'rm -f -- "$HOME/.config/tmux-user/profile"', '"dandavison/delta"', '"Wilfred/difftastic"',
            'install_docker', 'rustup', 'cs install metals', 'brew install go', 'brew install openjdk',
            'install_oh_my_posh', 'install_nerd_font', 'configure_terminal_font', 'zsh-autosuggestions',
            'install_shell_integration full', 'install_tmux_plugins', 'install_herdr_workbench',
            '[ "$WANT_NVIM" != 1 ] || install_neovim', 'check_install_tools desktop'], label='full')
        self.assertNotIn('clone_config tmux ', self.setup)
        self.assertNotIn('clone_config tmux\n', self.setup)
        # Neovim's checkout is cloned only when asked for or already there.
        self.assertRegex(self.setup, r'if \[ "\$WANT_NVIM" = 1 \]; then\n  clone_config nvim')

    def test_windows_default_is_the_workbench_and_full_adds_the_rest(self):
        self.assertIn('$wantFull = ($env:INSTALL_FULL -eq "1")', self.windows)
        self.assertIn('$extras = if ($wantFull) { @("nodejs", "go", "openjdk") } else { @() }', self.windows)
        heavy = block(self.windows, 'if ($wantFull) {\n    try {\n        # Rust', '} else {\n    Write-Host "  Toolchains')
        self.assert_each(heavy, ['rustup', 'cs install metals', 'winget install Docker.DockerDesktop'], label='windows-full')
        before = self.windows[:self.windows.index('if ($wantFull) {\n    try {\n        # Rust')]
        self.assert_each(before, ['rustup-msvc', 'Docker.DockerDesktop'], present=False, label='windows-default')


if __name__ == '__main__':
    unittest.main()
