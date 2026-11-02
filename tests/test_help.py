"""The help reference must stay complete and readable at real terminal widths."""
import csv
import importlib.util
import os
from pathlib import Path
import pty
import re
import struct
import subprocess
import sys
import termios
import fcntl
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('help_layout', ROOT / 'scripts/help.py')
help_layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(help_layout)


class HelpLayoutTests(unittest.TestCase):
    def test_reference_never_exceeds_its_terminal_width(self):
        for width in (20, 30, 40, 66, 80, 95, 96, 100, 143, 144, 168, 202):
            with self.subTest(width=width):
                lines = help_layout.render(width).splitlines()
                self.assertTrue(all(help_layout.cells(line) <= width for line in lines))
                self.assertIn('Backspace', '\n'.join(lines))

    def test_each_registered_action_is_described_once(self):
        rendered = help_layout.render(168)
        with (ROOT / 'actions.tsv').open() as stream:
            for row in csv.DictReader(stream, delimiter='\t'):
                with self.subTest(action=row['id']):
                    pattern = r'(?<!\S)' + re.escape(row['key']) + r' {2,}' + re.escape(row['label']) + r'(?= {2,}|$)'
                    self.assertEqual(len(re.findall(pattern, rendered, re.MULTILINE)), 1)

    def test_main_reference_fits_the_current_popup_first_screen(self):
        lines = help_layout.render(168).splitlines()
        # A 200x57 client gives a 168x46 interior and 45 pager content rows.
        self.assertIn('ta         Attach or create tmux session', '\n'.join(lines[:45]))
        for title in ('Panes', 'Windows & sessions', 'Tools & projects',
                      'Search & reference', 'Copy mode (no prefix)', 'Help & plugins'):
            self.assertIn(title, '\n'.join(lines[:45]))
        self.assertIn('Lazygit (no prefix)', '\n'.join(lines[45:]))
        self.assertLess(len(lines), 73)

    def test_colors_do_not_change_alignment_or_content(self):
        colored = help_layout.render(168, color=True)
        self.assertIn('\033[', colored)
        self.assertEqual(help_layout.ANSI.sub('', colored), help_layout.render(168))

    def test_piped_output_uses_input_terminal_size(self):
        master, slave = pty.openpty()
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 18, 66, 0, 0))
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/help.py'), '--plain'],
                                    stdin=slave, capture_output=True, text=True,
                                    env=dict(os.environ, COLUMNS='200'), timeout=10)
        finally:
            os.close(master)
            os.close(slave)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, help_layout.render(66))

    def test_fill_pads_to_the_input_terminal_height(self):
        master, slave = pty.openpty()
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 200, 66, 0, 0))
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/help.py'), '--plain', '--fill'],
                                    stdin=slave, capture_output=True, text=True, timeout=10)
        finally:
            os.close(master)
            os.close(slave)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith(help_layout.render(66)))
        self.assertEqual(result.stdout.count('\n'), 199)  # one pager row is the prompt

    def test_long_and_wide_characters_are_wrapped_without_loss(self):
        text = '界' * 19 + ' unbroken_token_' * 5
        wrapped = help_layout.wrap(text, 18)
        self.assertTrue(all(help_layout.cells(line) <= 18 for line in wrapped))
        self.assertEqual(''.join(wrapped).replace(' ', ''), text.replace(' ', ''))


if __name__ == '__main__':
    unittest.main()
