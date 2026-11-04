#!/usr/bin/env python3
"""Render the shortcut reference in columns sized to the actual popup terminal."""
import argparse
import csv
from itertools import combinations
import os
from pathlib import Path
import re
import sys
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
RESET = '\033[0m'
HEADING = '\033[1;38;2;136;192;208m'
KEY = '\033[1;38;2;236;239;244m'
MUTED = '\033[38;2;216;222;233m'
ANSI = re.compile(r'\033\[[0-9;]*m')
ORDER = ('Panes', 'Windows & sessions', 'Tools & projects', 'Search & reference',
         'Remote', 'Agents', 'Copy mode (no prefix)', 'Help & plugins', 'Shell (full setup)')
REFERENCES = ('Helix (no prefix)', 'Lazygit (no prefix)', 'Btop (no prefix)', 'Git aliases (full setup)')
ACTION_GROUPS = {
    **dict.fromkeys(('git', 'github', 'docker', 'top', 'info', 'shell', 'notes', 'projects', 'llm', 'open-file'), 'Tools & projects'),
    **dict.fromkeys(('history', 'search', 'scoped-search', 'ai', 'man', 'cheat', 'tldr'), 'Search & reference'),
    **dict.fromkeys(('palette', 'help', 'update', 'themes', 'special-days', 'pick', 'urls', 'editor-help'), 'Help & plugins'),
    **dict.fromkeys(('new-session', 'rename-session', 'rename-window'), 'Windows & sessions'),
    'ssh': 'Remote', 'ssh-split': 'Remote',
}


def cells(text):
    return sum(0 if unicodedata.combining(char) else
               2 if unicodedata.east_asian_width(char) in ('W', 'F') else 1
               for char in ANSI.sub('', text))


def wrap(text, width):
    """Wrap at spaces where possible; split long tokens without dropping text."""
    text = ' '.join(text.split())
    result = []
    while cells(text) > width:
        used = split = 0
        for index, char in enumerate(text):
            used += cells(char)
            if used > width:
                split = index
                break
        if not split:
            # A wide glyph on a one-cell terminal cannot fit; keep it intact.
            split = 1
        space = text.rfind(' ', 0, split + 1)
        if space > 0:
            split = space
        result.append(text[:split])
        text = text[split:].lstrip()
    result.append(text)
    return result


def current_host():
    """tmux or herdr: which multiplexer's keys the reference describes."""
    if os.environ.get('TMUX'):
        return 'tmux'
    return 'herdr' if os.environ.get('HERDR_ENV') == '1' else 'tmux'


def applies(row, host):
    return row.get('hosts', 'all') in ('all', host)


def sections(root=ROOT, host=None):
    host = host or current_host()
    groups = {title: [] for title in (*ORDER, *REFERENCES)}
    with (root / 'help.tsv').open() as stream:
        for row in csv.DictReader(stream, delimiter='\t'):
            if applies(row, host):
                groups.setdefault(row['section'], []).append((row['key'], row['description']))
    with (root / 'actions.tsv').open() as stream:
        for row in csv.DictReader(stream, delimiter='\t'):
            if applies(row, host):
                title = ACTION_GROUPS.get(row['id'], 'Other commands')
                groups.setdefault(title, []).append((row['key'], row['label']))
    return [(title, items) for title, items in groups.items() if items]


def style(text, color, enabled):
    return color + text + RESET if enabled and text else text


def section_lines(title, items, width, color):
    result = [style(line, HEADING, color) for line in wrap(title, width)] + ['']
    key_width = 9
    description_width = max(1, width - key_width - 2)
    for key, description in items:
        if cells(key) > key_width or width < 24:
            result.extend(style(line, KEY, color) for line in wrap(key, width))
            result.extend('  ' + line for line in wrap(description, max(1, width - 2)))
            continue
        for index, line in enumerate(wrap(description, description_width)):
            key_text = key if index == 0 else ''
            result.append(style(key_text, KEY, color) + ' ' * (key_width - cells(key_text) + 2) + line)
    return result


def columns(groups, width, count, color):
    gutter = 4
    count = min(count, len(groups))
    if not count:
        return []
    col_width = (width - gutter * (count - 1)) // count
    blocks = [section_lines(title, items, col_width, color) for title, items in groups]
    # Keep sections intact and reading order stable; balance contiguous columns.
    best = None
    for cuts in combinations(range(1, len(blocks)), count - 1):
        boundaries = (0, *cuts, len(blocks))
        heights = [sum(len(block) for block in blocks[a:b]) + 2 * (b - a - 1)
                   for a, b in zip(boundaries, boundaries[1:])]
        score = (max(heights), sum(height * height for height in heights))
        if best is None or score < best[0]:
            best = score, boundaries
    packed = []
    for start, end in zip(best[1], best[1][1:]):
        content = []
        for index, block in enumerate(blocks[start:end]):
            if index:
                content.extend(['', ''])
            content.extend(block)
        packed.append(content)
    rows = []
    for row in range(max(map(len, packed))):
        parts = []
        for column in packed:
            text = column[row] if row < len(column) else ''
            parts.append(text + ' ' * (col_width - cells(text)))
        rows.append((' ' * gutter).join(parts).rstrip())
    return rows


def render(width, color=False, root=ROOT, palette=True, host=None):
    host = host or current_host()
    width = max(20, width)
    padding = 2 if width >= 40 else 1
    usable = width - 2 * padding
    count = 3 if width >= 144 else 2 if width >= 96 else 1
    groups = sections(root, host)
    primary = [(title, items) for title, items in groups if title not in REFERENCES]
    reference = [(title, items) for title, items in groups if title in REFERENCES]
    title, prefix = ('HERDR SHORTCUTS' if host == 'herdr' else 'TMUX SHORTCUTS'), 'Prefix: Ctrl-a'
    if cells(title) + cells(prefix) + 4 <= usable:
        heading = style(title, HEADING, color) + ' ' * (usable - cells(title) - cells(prefix)) + style(prefix, KEY, color)
        lines = [heading]
    else:
        lines = [style(title, HEADING, color), style(prefix, KEY, color)]
    hint = ('F: search commands   |   ' if palette else '') + 'Space/b: page   |   /: search   |   q: close'
    for line in ([hint] if cells(hint) <= usable else wrap(hint, usable)):
        lines.append(style(line, MUTED, color))
    lines.extend(['', ''])
    lines.extend(columns(primary, usable, count, color))
    lines.extend(['', ''])
    lines.append(style('TOOL REFERENCE', HEADING, color))
    lines.extend(style(line, MUTED, color) for line in wrap('Keys below act inside each tool; aliases run in the shell.', usable))
    lines.append('')
    lines.extend(columns(reference, usable, count, color))
    return '\n'.join(' ' * padding + line if line else '' for line in lines) + '\n'


def terminal_size():
    # stdout is piped into less, so read the popup's input terminal instead.
    for fd in (0, 2, 1):
        try:
            return os.get_terminal_size(fd)
        except OSError:
            pass
    return os.terminal_size((80, 24))


def terminal_width():
    return terminal_size().columns


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--width', type=int, help='output width in terminal cells')
    parser.add_argument('--plain', action='store_true', help='omit terminal colors')
    parser.add_argument('--host', choices=('tmux', 'herdr'), help='which multiplexer the keys belong to (default: detected)')
    parser.add_argument('--no-palette', action='store_true',
                        help='omit the F hint when the pager cannot hand over to the palette')
    parser.add_argument('--fill', action='store_true',
                        help='pad to the input terminal height: less draws a shorter file at the '
                             'bottom of the screen and G scrolls "~" rows in above it')
    args = parser.parse_args(argv)
    colored = not args.plain and sys.stdin.isatty()
    if colored:
        from appearance import current_theme
        palette = current_theme()[1]['colors']
        def ansi(hex_color, bold=False):
            rgb = ';'.join(str(int(hex_color[index:index + 2], 16)) for index in (1, 3, 5))
            return '\033[' + ('1;' if bold else '') + '38;2;' + rgb + 'm'
        global HEADING, KEY, MUTED
        HEADING = ansi(palette['accent'], True)
        KEY = ansi(palette['foreground'], True)
        MUTED = ansi(palette['muted'])
    text = render(args.width or terminal_width(), color=colored, palette=not args.no_palette, host=args.host)
    if args.fill:
        text += '\n' * max(0, terminal_size().lines - 1 - text.count('\n'))
    sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
