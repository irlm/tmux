"""Exercise holiday dates, replay, and first-attachment greetings."""
from datetime import date
import fcntl
import importlib.util
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / 'scripts/special_days.py'
spec = importlib.util.spec_from_file_location('special_days', SCRIPT)
special_days = importlib.util.module_from_spec(spec)
spec.loader.exec_module(special_days)
scene_spec = importlib.util.spec_from_file_location('special_day_scenes', REPO / 'scripts/special_day_scenes.py')
scenes = importlib.util.module_from_spec(scene_spec)
scene_spec.loader.exec_module(scenes)


class SpecialDayTests(unittest.TestCase):
    def cli(self, *args, env=None):
        return subprocess.run([sys.executable, str(SCRIPT), *args], env=env,
                              text=True, capture_output=True, timeout=10)

    def test_special_dates_have_single_line_ascii_motifs(self):
        expected = {'2027-01-01': 'New Year', '2026-02-14': "Valentine's",
                    '2026-03-17': "St. Patrick's", '2026-07-04': 'July 4',
                    '2026-10-31': 'Halloween', '2026-12-25': 'Christmas',
                    '2026-12-31': "New Year's Eve"}
        for day, label in expected.items():
            with self.subTest(day=day):
                result = self.cli('--date', day, '--status')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(label, result.stdout)
                self.assertEqual(len(result.stdout.splitlines()), 1)
                self.assertTrue(result.stdout.isascii())

    def test_ordinary_days_produce_no_output(self):
        for day in ('2026-10-30', '2026-11-01', '2026-07-03', '2028-02-29'):
            result = self.cli('--date', day, '--status')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, '')

    def test_thanksgiving_tracks_the_fourth_thursday(self):
        for year, november_day in ((2024, 28), (2025, 27), (2026, 26), (2027, 25), (2029, 22)):
            self.assertEqual(special_days.celebration_on(date(year, 11, november_day)), 'thanksgiving')
            self.assertIsNone(special_days.celebration_on(date(year, 11, november_day - 7)))
            self.assertIsNone(special_days.celebration_on(date(year, 11, november_day + 1)))

    def test_default_uses_the_local_calendar(self):
        with mock.patch.object(special_days, 'date') as clock, mock.patch('sys.stdout') as output:
            clock.today.return_value = date(2026, 10, 31)
            special_days.main(['--status'])
            self.assertIn('Halloween', ''.join(call.args[0] for call in output.write.call_args_list))

    def test_replay_works_on_any_date_and_fits_the_preview(self):
        for identifier in special_days.CELEBRATIONS:
            result = self.cli('--date', '2026-11-01', '--play', identifier, '--plain', '--width', '30')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(special_days.CELEBRATIONS[identifier].name, result.stdout)
            self.assertTrue(result.stdout.isascii())
            self.assertNotIn('\033', result.stdout)
            self.assertTrue(all(len(line) <= 30 for line in result.stdout.splitlines()))
            self.assertGreater(len(result.stdout.splitlines()), 5)

    def test_fireworks_stay_within_the_terminal(self):
        for width, height in ((1, 3), (38, 8), (138, 12)):
            for banner in ('', 'USA', '2027'):
                for frame in range(scenes.FRAME_COUNT):
                    lines = scenes.fireworks_frame(width, height, frame, banner=banner)
                    self.assertEqual(len(lines), height)
                    self.assertTrue(all(len(line) <= width and line.isascii() for line in lines))
        self.assertIn('*', ''.join(scenes.fireworks_frame(60, 12, 9)))

    def test_every_celebration_moves_within_a_fixed_ascii_canvas(self):
        for identifier, event in special_days.CELEBRATIONS.items():
            for width, height in ((1, 1), (38, 8), (96, 16)):
                with self.subTest(event=identifier, size=(width, height)):
                    frames = [scenes.scene_frame(identifier, event.art, width, height, frame, event.fireworks)
                              for frame in range(scenes.FRAME_COUNT)]
                    self.assertTrue(all(len(frame) == height for frame in frames))
                    self.assertTrue(all(len(line) == width and line.isascii() for frame in frames for line in frame))
                    if width >= 38:
                        self.assertGreater(len({tuple(frame) for frame in frames}), 8)

    def test_invalid_date_is_reported(self):
        result = self.cli('--date', '2026-02-30')
        self.assertEqual(result.returncode, 2)
        self.assertIn('invalid', result.stderr)

    def test_firework_titles_show_usa_and_the_celebration_year(self):
        for identifier, day, label in (('july-4', '2026-07-04', 'U S A'),
                                       ('new-year', '2026-11-01', '2027'),
                                       ('new-years-eve', '2026-12-31', '2027'),
                                       ('new-year', '2027-01-01', '2027'),
                                       ('new-years-eve', '2030-12-31', '2031')):
            with self.subTest(event=identifier, date=day):
                result = self.cli('--date', day, '--play', identifier, '--plain', '--width', '40')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(label, result.stdout.splitlines()[0])
                self.assertTrue(all(len(line) <= 40 for line in result.stdout.splitlines()))
                self.assertTrue(result.stdout.isascii())

    def test_firework_sparks_finish_in_the_complete_lettering(self):
        for label in ('USA', '2027', '2031'):
            letters = scenes.banner_rows(label, 60, 12)
            top, left = (12 - len(letters)) // 2, (60 - len(letters[0])) // 2
            for frame, variation in ((32, 0), (35, 13), (47, 65535)):
                with self.subTest(text=label, frame=frame, variation=variation):
                    picture = scenes.fireworks_frame(60, 12, frame, variation, banner=label)
                    visible = tuple(row[left:left + len(letters[0])] for row in picture[top:top + len(letters)])
                    self.assertEqual(visible, letters)
                    self.assertTrue(any('*' in row for row in visible))

    def test_letter_rockets_depend_on_the_word_and_finish_near_the_end(self):
        usa = scenes.fireworks_frame(60, 12, 4, 7, banner='USA')
        year = scenes.fireworks_frame(60, 12, 4, 7, banner='2027')
        self.assertNotEqual(usa, year, 'Letter rockets used the same unrelated flight path')
        self.assertIn('^', ''.join(usa))
        letters = scenes.banner_rows('2027', 60, 12)
        top, left = (12 - len(letters)) // 2, (60 - len(letters[0])) // 2
        for frame in (0, 10, 20, 25):
            picture = scenes.fireworks_frame(60, 12, frame, 7, banner='2027')
            visible = tuple(row[left:left + len(letters[0])] for row in picture[top:top + len(letters)])
            self.assertNotEqual(visible, letters)

    def test_letters_and_year_digits_form_in_separate_sky_positions(self):
        for label, arrivals in (('USA', (10, 15, 20)), ('2027', (10, 14, 18, 22))):
            positions = []
            for index, (char, frame) in enumerate(zip(label, arrivals)):
                picture = scenes.fireworks_frame(96, 16, frame, 0, banner=label)
                glyph = scenes.LETTERS[char]
                matches = [(x, y) for y in range(12) for x in range(92)
                           if tuple(row[x:x + 5] for row in picture[y:y + 5]) == glyph
                           and index * 96 / len(label) <= x < (index + 1) * 96 / len(label)]
                self.assertTrue(matches, f'{label}: {char} did not form separately at frame {frame}')
                positions.append(matches[0])
            self.assertEqual(len(set(positions)), len(label))
            self.assertGreater(len({y for _, y in positions}), 1)

    def test_ordinary_fireworks_remain_visible_alongside_letter_rockets(self):
        picture = scenes.fireworks_frame(96, 16, 8, 0, banner='USA')
        # This upper-middle area is away from the U and the next letter's rocket.
        other_burst = ''.join(row[24:40] for row in picture[:8])
        self.assertTrue(any(char in '*+.' for char in other_burst))

    def test_short_firework_canvases_keep_readable_lettering(self):
        for label, expected in (('USA', 'U S A'), ('2027', '2027')):
            picture = scenes.fireworks_frame(38, 3, scenes.FRAME_COUNT - 1, banner=label)
            self.assertIn(expected, '\n'.join(picture))
            self.assertTrue(all(len(line) == 38 and line.isascii() for line in picture))

    def test_replay_variations_change_the_scene_and_remain_reproducible(self):
        for identifier, event in special_days.CELEBRATIONS.items():
            with self.subTest(event=identifier):
                def movie(variation):
                    return [scenes.scene_frame(identifier, event.art, 60, 12, frame,
                                               event.fireworks, variation)
                            for frame in range(scenes.FRAME_COUNT)]
                original = movie(0)
                self.assertEqual(original, movie(0))
                self.assertNotEqual(original, movie(1))
                alternate = movie(65535)
                self.assertTrue(all(len(line) == 60 and line.isascii() for frame in alternate for line in frame))

    def test_ordinary_attachment_does_not_create_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp) / 'state'
            result = self.cli('--auto', '--client', '/dev/unused', '--date', '2026-11-01',
                              env=dict(os.environ, TMUX_DATA_DIR=str(directory)))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(directory.exists())


@unittest.skipUnless(shutil.which('tmux'), 'tmux is not installed')
class SpecialDayTerminalTests(unittest.TestCase):
    def test_motion_finishes_without_redraws_and_replays_on_request(self):
        with tempfile.TemporaryDirectory(prefix='tmux-art-playback-') as tmp:
            root = Path(tmp)
            wrapper = root / 'tmux'
            wrapper.write_text('#!/bin/sh\nprintf "." >> "$TEST_CALLS"\nprintf "%s\\n" "$TEST_MOTION"\n')
            wrapper.chmod(0o755)
            for motion in ('on', 'off'):
                with self.subTest(motion=motion):
                    master, slave = pty.openpty()
                    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
                    original_mode = termios.tcgetattr(slave)
                    env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'],
                               TEST_MOTION=motion, TMUX_THEME_DIR=str(root / 'theme'),
                               TEST_CALLS=str(root / ('calls-' + motion)),
                               COLUMNS='300', LINES='100')
                    env.pop('FZF_PREVIEW_COLUMNS', None)
                    process = subprocess.Popen([sys.executable, str(SCRIPT), '--play', 'halloween'],
                                               env=env, stdin=slave, stdout=slave, stderr=slave)
                    output = bytearray()

                    def collect(seconds, until=None):
                        deadline = time.monotonic() + seconds
                        while time.monotonic() < deadline:
                            ready, _, _ = select.select([master], [], [], max(0, deadline - time.monotonic()))
                            if ready:
                                output.extend(os.read(master, 65536))
                                if until and until in output:
                                    return

                    try:
                        collect(7, b'r: replay')
                        self.assertIn(b'r: replay', output)
                        self.assertIsNone(process.poll())
                        collect(.1)
                        settled = len(output)
                        collect(.3)
                        self.assertEqual(len(output), settled, 'Finished artwork kept redrawing')
                        positions = re.findall(rb'\033\[(\d+);(\d+)H', output)
                        self.assertTrue(positions)
                        self.assertTrue(all(int(row) <= 24 and int(column) <= 80 for row, column in positions))
                        if motion == 'on':
                            output.clear()
                            os.write(master, b'r')
                            collect(2, b'r: restart')
                            self.assertIn(b'r: restart', output)
                        for key, title in ((b'n', b'Happy Thanksgiving!'), (b'p', b'Happy Halloween!')):
                            output.clear()
                            os.write(master, key)
                            collect(2, title)
                            self.assertIn(title, output)
                            self.assertIsNone(process.poll())
                        self.assertEqual((root / ('calls-' + motion)).read_text(), '.',
                                         'Switching holidays relaunched a tmux helper')
                        os.write(master, b'q')
                        # Keep consuming terminal output while the child drains it
                        # and restores its tty; wait() alone can block that drain.
                        closing_deadline = time.monotonic() + 3
                        while process.poll() is None and time.monotonic() < closing_deadline:
                            collect(min(.05, max(0, closing_deadline - time.monotonic())))
                        process.wait(timeout=max(0, closing_deadline - time.monotonic()))
                        collect(.1)
                        self.assertEqual(process.returncode, 0, output.decode(errors='replace'))
                        restored_mode = termios.tcgetattr(slave)
                        # Darwin can mark pending input when canonical mode returns.
                        restored_mode[3] &= ~getattr(termios, 'PENDIN', 0)
                        original_mode[3] &= ~getattr(termios, 'PENDIN', 0)
                        self.assertEqual(restored_mode, original_mode)
                        self.assertIn(b'\033[?25h', output)
                    finally:
                        if process.poll() is None:
                            process.terminate()
                            process.wait(timeout=3)
                        os.close(master)
                        os.close(slave)

    def test_first_attachment_greets_once_and_leaves_one_client(self):
        with tempfile.TemporaryDirectory(prefix='tmux-special-days-') as tmp:
            root = Path(tmp).resolve()
            socket = str(root / 'socket')
            binary = shutil.which('tmux')
            wrappers = root / 'bin'
            wrappers.mkdir()
            wrapper = wrappers / 'tmux'
            wrapper.write_text('#!/bin/sh\nexec ' + shlex.quote(binary) + ' -S ' + shlex.quote(socket) + ' "$@"\n')
            wrapper.chmod(0o755)
            env = dict(os.environ, PATH=str(wrappers) + ':' + os.environ['PATH'],
                       TERM='xterm-256color', TMUX_DATA_DIR=str(root / 'data'),
                       TMUX_THEME_DIR=str(root / 'theme'))
            env.pop('TMUX', None)
            env.pop('TMUX_PANE', None)

            def tm(*arguments):
                return subprocess.run([binary, '-S', socket, *arguments], env=env,
                                      capture_output=True, text=True, timeout=10)

            result = tm('-f', '/dev/null', 'new-session', '-d', '-s', 'greeting', '/bin/sh')
            self.assertEqual(result.returncode, 0, result.stderr)
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            output = bytearray()

            def drain():
                try:
                    while True:
                        chunk = os.read(master, 65536)
                        if not chunk:
                            break
                        output.extend(chunk)
                except OSError:
                    pass

            client = None
            try:
                command = shlex.join([sys.executable, str(SCRIPT), '--auto', '--date', '2026-07-04'])
                hook = 'run-shell -b ' + shlex.quote(command + ' --client #{q:client_name}')
                result = tm('set-hook', '-g', 'client-attached[90]', hook)
                self.assertEqual(result.returncode, 0, result.stderr)
                client = subprocess.Popen([binary, '-S', socket, 'attach-session', '-t', 'greeting'],
                                          env=env, stdin=slave, stdout=slave, stderr=slave)
                os.close(slave)
                slave = None
                threading.Thread(target=drain, daemon=True).start()
                deadline = time.monotonic() + 5
                while b'Happy 4th of July!' not in output and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertIn(b'Happy 4th of July!', output)
                os.write(master, b'q')
                stamp = root / 'data/special-days/2026-07-04'
                self.assertTrue(stamp.is_dir())
                tty = tm('list-clients', '-F', '#{client_name}').stdout.strip()
                self.assertEqual(len(tty.splitlines()), 1)
                time.sleep(.1)
                previous_output = len(output)
                result = subprocess.run([sys.executable, str(SCRIPT), '--auto', '--date', '2026-07-04',
                                         '--client', tty], env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                time.sleep(.1)
                self.assertNotIn(b'Happy 4th of July!', output[previous_output:])
                self.assertEqual(list(stamp.parent.iterdir()), [stamp])
                self.assertIsNone(client.poll(), 'Greeting terminated the parent client')
                self.assertEqual(tm('display-message', '-p', '-c', tty, '#{client_width}x#{client_height}').stdout.strip(), '80x24')
            finally:
                tm('kill-server')
                if client is not None:
                    client.wait(timeout=3)
                if slave is not None:
                    os.close(slave)
                os.close(master)
