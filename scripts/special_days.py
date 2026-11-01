#!/usr/bin/env python3
"""Local-calendar ASCII celebrations, with optional terminal fireworks."""
import argparse
from datetime import date
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
from typing import NamedTuple


class Celebration(NamedTuple):
    name: str
    when: str
    motif: str
    art: str
    fireworks: bool = False


CELEBRATIONS = {
    'new-year': Celebration('Happy New Year!', 'January 1', r'\o/ New Year',
                           ' \\ | /     *     \\ | /\n-- * --   \\o/   -- * --\n / | \\           / | \\', True),
    'valentine': Celebration("Valentine's Day", 'February 14', "<3 Valentine's",
                            " .-.-.\n(     )\n '. .'\n   '"),
    'st-patrick': Celebration("St. Patrick's Day", 'March 17', "(_|_) St. Patrick's",
                             '   _\n _(_) _\n(_) |(_)\n   /'),
    'july-4': Celebration('Happy 4th of July!', 'July 4', r'\|/ July 4',
                         ' \\ | /   *   \\ | /\n-- * --     -- * --\n / | \\   *   / | \\', True),
    'halloween': Celebration('Happy Halloween!', 'October 31', '(^v^) Halloween',
                            "   _|_\n .'   '.\n/ ^   ^ \\\n\\  \\_/  /\n '-----'"),
    'thanksgiving': Celebration('Happy Thanksgiving!', 'Fourth Thursday in November',
                               r'\|||/ Thanksgiving', ' \\|||/\n (o o)\n / v \\\n/_____\\\n  / \\'),
    'christmas': Celebration('Merry Christmas!', 'December 25', r'*/_\ Christmas',
                            '    *\n   /_\\\n  /___\\\n /_____\\\n    |'),
    'new-years-eve': Celebration("New Year's Eve!", 'December 31', r"\o/ New Year's Eve",
                                ' \\ | /    *    \\ | /\n-- * --  3 2 1 -- * --\n / | \\         / | \\', True),
}
FIXED_DAYS = {(1, 1): 'new-year', (2, 14): 'valentine', (3, 17): 'st-patrick',
              (7, 4): 'july-4', (10, 31): 'halloween', (12, 25): 'christmas',
              (12, 31): 'new-years-eve'}


def celebration_on(day):
    if day.month == 11 and day.weekday() == 3 and 22 <= day.day <= 28:
        return 'thanksgiving'
    return FIXED_DAYS.get((day.month, day.day))


def artwork(identifier, width=80):
    event = CELEBRATIONS[identifier]
    lines = [event.name, '', *event.art.splitlines(), '', event.when]
    return '\n'.join(line[:width].center(width).rstrip() for line in lines) + '\n'


def tmux(*arguments):
    return subprocess.run(['tmux', *arguments], text=True, capture_output=True,
                          timeout=10)


def play(identifier, auto_close=False, plain=False, columns=None):
    try:
        width, height = os.get_terminal_size(sys.stdout.fileno())
    except OSError:
        width, height = shutil.get_terminal_size((80, 24))
    preview_width = os.environ.get('FZF_PREVIEW_COLUMNS', '')
    width = max(1, (columns or (int(preview_width) if preview_width.isdigit() else width)) - 2)
    if plain or not (sys.stdin.isatty() and sys.stdout.isatty()):
        print(artwork(identifier, width), end='')
        return

    # Imported only for interactive Unix terminals; text previews stay portable.
    import termios
    import tty
    import select
    import time
    import random
    from appearance import current_theme
    from special_day_scenes import FPS, FRAME_COUNT, MAX_WIDTH, MAX_HEIGHT, scene_frame

    palette = current_theme()[1]['colors']
    colors = []
    for role in ('accent', 'yellow', 'magenta'):
        rgb = ';'.join(str(int(palette[role][index:index + 2], 16)) for index in (1, 3, 5))
        colors.append('' if 'NO_COLOR' in os.environ else '\033[38;2;' + rgb + 'm')
    old = termios.tcgetattr(sys.stdin)
    previous = [''] * max(1, height - 1)
    controls = 'n/p: holiday | Enter/q/Esc: close' if width >= 52 else 'n/p: art | q: close'
    hint = 'Enter / q / Esc: close' if auto_close else 'r: replay | ' + controls
    playing_hint = 'Enter / q / Esc: close' if auto_close else 'r: restart | ' + controls
    scene_width, scene_height = min(width, MAX_WIDTH), max(1, min(MAX_HEIGHT, height - 6))
    identifiers = tuple(CELEBRATIONS)
    randomizer = random.Random()
    variation = 0

    def wait_action(seconds=None):
        deadline = None if seconds is None else time.monotonic() + seconds
        while True:
            remaining = None if deadline is None else max(0, deadline - time.monotonic())
            ready, _, _ = select.select([sys.stdin], [], [], remaining)
            if not ready:
                return None
            keys = os.read(sys.stdin.fileno(), 32)
            if not keys or any(key in keys for key in (b'q', b'\x1b', b'\n', b'\r', b'\x03')):
                return 'close'
            if not auto_close:
                for key, action in ((b'r', 'replay'), (b'n', 'next'), (b'p', 'previous')):
                    if key in keys.lower():
                        return action

    def draw(lines, color):
        visible = lines[:max(1, height - 1)]
        top = max(0, (height - 1 - len(visible)) // 2)
        rows = [''] * top + visible + [''] * max(0, height - 1 - top - len(visible))
        output = []
        for row, line in enumerate(rows):
            line = line[:width]
            # Keep the canvas coordinates fixed; emit only rows that changed.
            column = 1 + (width - len(line)) // 2
            text = line.rstrip()
            decorated = top + 2 <= row < top + len(visible) - 2
            rendered = (text, column, color, decorated) if text else ''
            if rendered != previous[row]:
                output.append(f'\033[{row + 1};1H\033[2K')
                if text:
                    painted = []
                    ink = None
                    for char in text:
                        next_ink = (colors[1] if char in '*o' else colors[2] if char in '+.' else color) if decorated else color
                        if next_ink != ink:
                            painted.append(next_ink)
                            ink = next_ink
                        painted.append(char)
                    output.append(f'\033[{row + 1};{column}H' + ''.join(painted) + '\033[0m')
                previous[row] = rendered
        if output:
            sys.stdout.write(''.join(output))
            sys.stdout.flush()

    try:
        tty.setcbreak(sys.stdin)
        sys.stdout.write('\033[?25l\033[2J')
        animated = tmux('show-option', '-gqv', '@special_days_motion').stdout.strip() != 'off'
        while True:
            event = CELEBRATIONS[identifier]
            variation = (variation + randomizer.randrange(1, 65536)) % 65536
            action = None
            if animated:
                started = time.monotonic()
                frame = 0
                while frame < FRAME_COUNT:
                    deadline = started + (frame + 1) / FPS
                    scene = scene_frame(identifier, event.art, scene_width, scene_height, frame, event.fireworks, variation)
                    draw([event.name, '', *scene, '', playing_hint], colors[0])
                    action = wait_action(max(0, deadline - time.monotonic()))
                    if action:
                        break
                    # Skip late frames instead of extending playback or catching up.
                    frame = max(frame + 1, int((time.monotonic() - started) * FPS))
            if action is None:
                draw([event.name, '', *event.art.splitlines(), '', hint], colors[0])
                # No redraw timer or polling while the finished scene waits for input.
                if auto_close:
                    wait_action(1.25)
                    return
                action = wait_action()
            if action == 'close':
                return
            if action in ('next', 'previous'):
                direction = 1 if action == 'next' else -1
                identifier = identifiers[(identifiers.index(identifier) + direction) % len(identifiers)]
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old)
        sys.stdout.write('\033[0m\033[?25h')
        sys.stdout.flush()


def auto_greet(client, day):
    identifier = celebration_on(day)
    if not identifier or not client:
        return
    if tmux('show-option', '-gqv', '@special_days').stdout.strip() == 'off':
        return
    result = tmux('display-message', '-p', '-c', client,
                  '#{client_width} #{client_height} #{client_control_mode}')
    if result.returncode:
        return
    fields = result.stdout.split()
    if len(fields) != 3 or not all(field.isdigit() for field in fields):
        return
    width, height, control = map(int, fields)
    if control or width < 60 or height < 18:
        return
    directory = Path(os.environ.get('TMUX_DATA_DIR',
                     str(Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'tmux')))
    stamps = directory / 'special-days'
    stamps.mkdir(parents=True, exist_ok=True, mode=0o700)
    stamp = stamps / day.isoformat()
    try:
        stamp.mkdir(mode=0o700)
    except FileExistsError:
        return
    command = shlex.join([sys.executable, str(Path(__file__).resolve()),
                          '--play', identifier, '--auto-close'])
    result = tmux('display-popup', '-c', client, '-w', '70%', '-h', '65%', '-E', command)
    if result.returncode:
        stamp.rmdir()  # A failed popup can retry at the next attachment.


def pick():
    listing = ''.join(f'{key}\t{event.name}\t{event.when}\n'
                      for key, event in CELEBRATIONS.items())
    preview = shlex.join([sys.executable, str(Path(__file__).resolve())]) + ' --play {1} --plain'
    result = subprocess.run(['fzf', '--delimiter=\t', '--with-nth=2..', '--prompt=Special day > ',
                             '--header=Enter: play art | Esc: cancel', '--preview=' + preview,
                             '--preview-window=right:50%:wrap'], input=listing,
                            stdout=subprocess.PIPE, text=True)
    identifier = result.stdout.split('\t', 1)[0].strip()
    if result.returncode == 0 and identifier in CELEBRATIONS:
        play(identifier)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--status', action='store_true', help='one-line motif for the local date')
    mode.add_argument('--auto', action='store_true', help='greet an attached tmux client once per special day')
    mode.add_argument('--pick', action='store_true', help='choose any celebration to replay')
    mode.add_argument('--play', choices=CELEBRATIONS, help='show a specific celebration')
    parser.add_argument('--date', type=date.fromisoformat, help='preview a date in YYYY-MM-DD form')
    parser.add_argument('--client', help='tmux client receiving an automatic greeting')
    parser.add_argument('--auto-close', action='store_true', help='close after a short greeting')
    parser.add_argument('--plain', action='store_true', help='print static ASCII art without terminal controls')
    parser.add_argument('--width', type=int, help='preview width in terminal cells')
    args = parser.parse_args(argv)
    if args.width is not None and args.width < 1:
        parser.error('--width must be positive')
    day = args.date or date.today()
    if args.auto:
        auto_greet(args.client, day)
    elif args.pick:
        pick()
    else:
        identifier = args.play or celebration_on(day)
        if identifier:
            if args.status:
                print(CELEBRATIONS[identifier].motif)
            else:
                play(identifier, args.auto_close, args.plain, args.width)


if __name__ == '__main__':
    main()
