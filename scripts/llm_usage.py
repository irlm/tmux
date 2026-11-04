#!/usr/bin/env python3
"""Show what the coding agents on this machine have consumed.

Claude Code and Codex keep a transcript per session with the token usage of
every reply. This reads the transcripts touched in the last week (cached per
file, so a popup costs a few milliseconds after the first run), adds the
live rate-limit windows from quota-axi when it is installed, and draws:

    LIMITS           remaining window budget and when it resets
    TOKENS BY DAY    last seven days, today last, and the whole window
    TOKENS BY MODEL  which models the tokens went to
"""
import argparse
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
import json
import re
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CACHE_DIR = Path(os.environ.get('TMUX_CACHE_DIR', str(Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'tmux')))
RESET = '\033[0m'
PLANS = {}  # provider -> plan name reported by quota-axi
SETUP = set()  # providers quota-axi reports as set up on this machine
BOLD = '\033[1m'
DIM = '\033[2m'


def human(count):
    for unit, size in (('B', 1e9), ('M', 1e6), ('K', 1e3)):
        if count >= size:
            return f'{count / size:.1f}{unit}'
    return str(int(count))


def pretty_model(model):
    """claude-opus-5-5 -> Opus 5.5; other vendors keep their own spelling."""
    if not model.startswith('claude-'):
        return model
    parts = model[len('claude-'):].split('-')
    if len(parts) >= 3 and parts[-1].isdigit() and parts[-2].isdigit():
        parts = parts[:-2] + [parts[-2] + '.' + parts[-1]]
    return ' '.join(part.capitalize() if part.isalpha() else part for part in parts)


def local_day(stamp):
    try:
        moment = datetime.fromisoformat(stamp.replace('Z', '+00:00'))
    except ValueError:
        return None
    return moment.astimezone().date().isoformat()


class Cache:
    """Per-file aggregates keyed by size and mtime; rewritten only on change."""

    def __init__(self, path):
        self.path = path
        self.dirty = False
        try:
            self.data = json.loads(path.read_text())
        except (OSError, ValueError):
            self.data = {}

    def entry(self, file, parse):
        stat = file.stat()
        signature = [stat.st_size, int(stat.st_mtime)]
        cached = self.data.get(str(file))
        if cached and cached.get('sig') == signature:
            return cached
        cached = {'sig': signature, **parse(file)}
        self.data[str(file)] = cached
        self.dirty = True
        return cached

    def save(self, keep):
        stale = [key for key in self.data if key not in keep]
        for key in stale:
            del self.data[key]
        if not (self.dirty or stale):
            return
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            temporary = self.path.with_suffix('.tmp')
            temporary.write_text(json.dumps(self.data))
            os.replace(temporary, self.path)
        except OSError:
            pass


def recent_files(directory, pattern, since):
    if not directory.is_dir():
        return []
    return [file for file in directory.rglob(pattern) if file.is_file() and file.stat().st_mtime >= since]


def parse_claude(file):
    """Assistant replies carry message.usage; one message can span lines."""
    days, models, seen = defaultdict(int), defaultdict(int), {}
    with file.open(encoding='utf-8', errors='replace') as stream:
        for line in stream:
            if '"usage"' not in line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            message = record.get('message') or {}
            usage = message.get('usage')
            if not isinstance(usage, dict) or message.get('role') != 'assistant':
                continue
            tokens = sum(int(usage.get(key) or 0) for key in
                         ('input_tokens', 'output_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens'))
            identity = message.get('id') or record.get('uuid')
            day = local_day(record.get('timestamp', ''))
            model = message.get('model') or 'unknown'
            if not day or model.startswith('<'):
                continue
            # Later lines of the same message repeat the usage: keep one.
            seen[identity] = (day, model, tokens)
    for day, model, tokens in seen.values():
        days[day] += tokens
        models[model] += tokens
    return {'days': days, 'models': models}


def parse_codex(file):
    """token_count events report the last turn; turn_context names the model."""
    days, models = defaultdict(int), defaultdict(int)
    model, limits = 'codex', None
    with file.open(encoding='utf-8', errors='replace') as stream:
        for line in stream:
            if '"turn_context"' in line:
                try:
                    model = (json.loads(line).get('payload') or {}).get('model') or model
                except ValueError:
                    pass
                continue
            if '"token_count"' not in line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            payload = record.get('payload') or {}
            info = payload.get('info') or {}
            usage = info.get('last_token_usage') or {}
            tokens = int(usage.get('total_tokens') or 0)
            day = local_day(record.get('timestamp', ''))
            if day and tokens:
                days[day] += tokens
                models[model] += tokens
            if payload.get('rate_limits'):
                limits = {'at': record.get('timestamp'), **payload['rate_limits']}
    return {'days': days, 'models': models, 'limits': limits}


def parse_antigravity(file):
    """Antigravity CLI steps carry input/cache/output tokens; the model is
    announced in the conversation when the user picks one."""
    days, models = defaultdict(int), defaultdict(int)
    model = 'antigravity'
    picked = re.compile(r'`Model Selection` from .*? to ([^\n.]+?)(?: \((?:High|Medium|Low)\))?\.')
    with file.open(encoding='utf-8', errors='replace') as stream:
        for line in stream:
            if 'MODEL' not in line and 'Model Selection' not in line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            content = record.get('content') or ''
            if 'Model Selection' in content:
                match = picked.search(content)
                if match:
                    model = match.group(1).strip()
            if record.get('source') != 'MODEL':
                continue
            tokens = sum(int(record.get(key) or 0) for key in ('input_tokens', 'cache_read_tokens', 'output_tokens'))
            day = local_day(record.get('created_at', ''))
            if day and tokens:
                days[day] += tokens
                models[model] += tokens
    return {'days': days, 'models': models}


# Every agent this can account for. Transcript-less providers still get a
# tab when quota-axi knows them, with their live windows only.
PROVIDERS = (
    ('claude', 'Claude Code', ('CLAUDE_CONFIG_DIR', '~/.claude', 'projects'), '*.jsonl', 'parse_claude'),
    ('codex', 'Codex', ('CODEX_HOME', '~/.codex', 'sessions'), '*.jsonl', 'parse_codex'),
    ('agy', 'Antigravity', ('ANTIGRAVITY_HOME', '~/.gemini/antigravity-cli', 'brain'), 'transcript.jsonl', 'parse_antigravity'),
    ('grok', 'Grok', ('GROK_HOME', '~/.grok', ''), None, None),
    ('copilot', 'Copilot', ('COPILOT_HOME', '~/.copilot', ''), None, None),
    ('cursor', 'Cursor', ('CURSOR_HOME', '~/.cursor', ''), None, None),
    ('kimi', 'Kimi', ('KIMI_HOME', '~/.kimi-code', ''), None, None),
)


def provider_dir(spec):
    env, default, sub = spec
    base = Path(os.environ.get(env, os.path.expanduser(default)))
    return base / sub if sub else base


def collect(provider, directory, pattern, parse, since, cache):
    totals = {'days': defaultdict(int), 'models': defaultdict(int), 'limits': None, 'files': 0}
    keep = set()
    for file in recent_files(directory, pattern, since):
        keep.add(str(file))
        entry = cache.entry(file, parse)
        totals['files'] += 1
        for day, tokens in entry['days'].items():
            totals['days'][day] += tokens
        for model, tokens in entry['models'].items():
            totals['models'][model] += tokens
        limits = entry.get('limits')
        if limits and (not totals['limits'] or limits.get('at', '') > totals['limits'].get('at', '')):
            totals['limits'] = limits
    cache.save(keep)
    return totals


def quota_windows(timeout=15):
    """Live windows from quota-axi: {provider: ([(label, used%, resets_at)], note)}.
    Fills PLANS and SETUP for every provider the tool knows."""
    if not shutil.which('quota-axi'):
        return {}
    try:
        result = subprocess.run(['quota-axi', '--json', '--max-age', '10m'], capture_output=True, text=True, timeout=timeout)
        report = json.loads(result.stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}
    windows = {}
    for entry in report.get('providers') or []:
        name = entry.get('provider')
        rows = []
        if not entry.get('notSetUp', False):
            SETUP.add(name)
        if entry.get('plan'):
            PLANS[name] = str(entry['plan'])
        for window in entry.get('windows') or []:
            remaining = window.get('percentRemaining')
            if remaining is None:
                continue
            rows.append((window.get('label') or window.get('id') or 'window', 100 - float(remaining), window.get('resetsAt')))
        state = entry.get('state') or {}
        note = ''
        if state.get('status') == 'auth_required':
            remedy = state.get('remedyCommand')
            note = ('run once: ' + remedy) if remedy and remedy != 'none' else (state.get('error') or 'sign-in required')
        elif state.get('stale'):
            note = 'stale reading'
        if rows or note:
            windows[name] = (rows, note)
    return windows


def codex_windows(limits):
    rows = []
    if not limits:
        return rows
    for key, label in (('primary', 'session'), ('secondary', 'week')):
        window = limits.get(key)
        if not window:
            continue
        minutes = window.get('window_minutes') or 0
        if minutes >= 10080:
            label = 'week'
        elif minutes:
            label = f'{minutes // 60}h'
        resets = window.get('resets_at')
        if isinstance(resets, (int, float)):
            resets = datetime.fromtimestamp(resets, tz=timezone.utc).isoformat()
        rows.append((label, float(window.get('used_percent') or 0), resets))
    return rows


def resets_in(stamp):
    if not stamp:
        return ''
    try:
        moment = datetime.fromisoformat(str(stamp).replace('Z', '+00:00'))
    except ValueError:
        return ''
    delta = moment - datetime.now(timezone.utc)
    if delta.total_seconds() <= 0:
        return 'Window passed; the reading is from the last session'
    days, rest = divmod(int(delta.total_seconds()), 86400)
    hours, rest = divmod(rest, 3600)
    if days:
        return f'Resets in {days}d {hours}h'
    return f'Resets in {hours}h {rest // 60}m'


class Painter:
    def __init__(self, enabled, palette):
        self.enabled = enabled
        self.palette = palette

    def color(self, role, bold=False):
        if not self.enabled:
            return ''
        value = self.palette.get(role, '#ffffff')
        rgb = ';'.join(str(int(value[index:index + 2], 16)) for index in (1, 3, 5))
        return '\033[' + ('1;' if bold else '') + '38;2;' + rgb + 'm'

    def paint(self, text, role, bold=False):
        return self.color(role, bold) + text + RESET if self.enabled else text

    def bar(self, fraction, width, role='accent'):
        filled = max(0, min(width, round(fraction * width)))
        return self.paint('━' * filled, role) + self.paint('━' * (width - filled), 'muted') if self.enabled \
            else '#' * filled + '-' * (width - filled)


def render(providers, windows, days, width, painter):
    width = max(40, width)
    label_width = 18
    lines = []
    today = date.today()
    day_keys = [(today - timedelta(days=offset)).isoformat() for offset in range(min(days, 7) - 1, -1, -1)]
    for title, totals, limit_rows, note in providers:
        lines.append(painter.paint(title, 'accent', True))
        lines.append('')
        lines.append(painter.paint('LIMITS', 'muted', True))
        if limit_rows:
            for label, used, resets in limit_rows:
                lines.append(f'  {label[:1].upper() + label[1:]:<{label_width}} {painter.bar(used / 100, width - label_width - 12)} {used:5.1f}%')
                lines.append('  ' + painter.paint(' ' * label_width + ' ' + resets_in(resets), 'muted'))
        else:
            lines.append('  ' + painter.paint(note or 'no live window data', 'muted'))
        lines.append('')
        lines.append(painter.paint('TOKENS BY DAY', 'muted', True))
        peak = max([totals['days'].get(day, 0) for day in day_keys] + [1])
        for day in day_keys:
            tokens = totals['days'].get(day, 0)
            name = 'Today' if day == today.isoformat() else date.fromisoformat(day).strftime('%a')
            name = painter.paint(f'{name:<{label_width}}', 'foreground', bold=(day == today.isoformat()))
            lines.append(f'  {name} {painter.bar(tokens / peak, width - label_width - 12)} {human(tokens):>7}')
        if days > 7:
            lines.append('  ' + painter.paint(f'{days} days'.ljust(label_width) + ' ' + ' ' * (width - label_width - 12) + f' {human(sum(totals["days"].values())):>7}', 'muted'))
        lines.append('')
        lines.append(painter.paint('TOKENS BY MODEL', 'muted', True))
        models = sorted(totals['models'].items(), key=lambda item: -item[1])
        peak = max([tokens for _, tokens in models] + [1])
        if not models:
            lines.append('  ' + painter.paint('nothing in the last %d days' % days, 'muted'))
        for model, tokens in models:
            bar_width = width - 14
            filled = max(len(pretty_model(model)) + 2, round(tokens / peak * bar_width))
            label = f' {pretty_model(model)} '.ljust(filled)
            if painter.enabled:
                lines.append('  ' + painter.color('selection') + '\033[7m' + painter.paint(label, 'foreground') + RESET + ' ' * (bar_width - filled) + f' {human(tokens):>7}')
            else:
                lines.append(f'  [{label}]'.ljust(bar_width + 4) + f' {human(tokens):>7}')
        lines.append('')
        lines.append('')
    return '\n'.join(lines).rstrip('\n') + '\n'


def gather(days, limits=True):
    """Every agent present on this machine: aggregates and live windows.
    An agent shows up when it left transcripts in the window or quota-axi
    says it is set up; Claude Code and Codex always do."""
    since = (datetime.now() - timedelta(days=days + 1)).timestamp()
    cache = Cache(CACHE_DIR / 'llm-usage.json')
    windows = quota_windows() if limits else {}
    providers = []
    for key, title, spec, pattern, parser in PROVIDERS:
        directory = provider_dir(spec)
        if parser:
            totals = collect(key, directory, pattern, globals()[parser], since, cache)
        else:
            totals = {'days': defaultdict(int), 'models': defaultdict(int), 'limits': None, 'files': 0}
        rows, note = windows.get(key, ([], ''))
        # A tab needs something to show: transcripts in the window or live
        # limit windows. "Set up but not signed in" stays out of the way.
        present = key in ('claude', 'codex') or totals['files'] or rows
        if not present:
            continue
        if key == 'codex':
            rows = rows or codex_windows(totals.get('limits'))
        if key == 'claude' and not rows and not note and not shutil.which('quota-axi'):
            note = 'quota-axi not installed'
        if not parser and not rows:
            note = note or 'no transcripts to read on this machine'
        totals['plan'] = PLANS.get(key, '')
        providers.append((title, totals, rows, note))
    return providers, windows


ICONS = {
    'Claude Code': ['  ╲ ╷ ╱  ', '  ─ ✦ ─  ', '  ╱ ╵ ╲  '],
    'Codex': ['  ╭───╮  ', '  │ ◇ │  ', '  ╰───╯  '],
    'Antigravity': ['   ▲ ▲   ', '  ╱ ◠ ╲  ', '  ‾‾‾‾‾  '],
    'Grok': ['  ╲   ╱  ', '    ╳    ', '  ╱   ╲  '],
    'Copilot': ['  ╭─◠─╮  ', '  │◉ ◉│  ', '  ╰───╯  '],
    'Cursor': ['  ◤      ', '  █▶     ', '  ◣      '],
    'Kimi': ['  ╭───╮  ', '  │ ✧ │  ', '  ╰───╯  '],
}


class Screen:
    """The interactive card: tabs per agent, limit, day and model bars."""

    def __init__(self, stdscr, providers, days, palette, refresh):
        self.stdscr = stdscr
        self.providers = providers
        self.days = days
        self.refresh = refresh
        self.tab = 0
        self.pairs = {}
        self.setup_colors(palette)

    def setup_colors(self, palette):
        import curses
        curses.start_color()
        curses.use_default_colors()
        roles = ('foreground', 'muted', 'accent', 'red', 'selection', 'background', 'yellow', 'green')
        basic = {'foreground': curses.COLOR_WHITE, 'muted': 8 if curses.COLORS > 8 else curses.COLOR_WHITE,
                 'accent': curses.COLOR_CYAN, 'red': curses.COLOR_RED, 'selection': 8 if curses.COLORS > 8 else curses.COLOR_BLUE,
                 'background': -1, 'yellow': curses.COLOR_YELLOW, 'green': curses.COLOR_GREEN}
        numbers = {}
        custom = curses.can_change_color() and curses.COLORS >= 256 and palette
        for index, role in enumerate(roles):
            if custom and role in palette:
                value = palette[role]
                number = 200 + index
                curses.init_color(number, *(int(value[i:i + 2], 16) * 1000 // 255 for i in (1, 3, 5)))
                numbers[role] = number
            else:
                numbers[role] = basic[role]
        pairs = [('text', 'foreground', -1), ('muted', 'muted', -1), ('accent', 'accent', -1), ('icon', 'red', -1),
                 ('fill', 'foreground', 'selection'), ('track', 'selection', -1), ('tab', 'foreground', 'selection'),
                 ('yellow', 'yellow', -1), ('green', 'green', -1)]
        for index, (name, fg, bg) in enumerate(pairs, start=1):
            curses.init_pair(index, numbers[fg], numbers[bg] if bg != -1 else -1)
            self.pairs[name] = curses.color_pair(index)

    def put(self, y, x, text, style='text', bold=False, width=None):
        import curses
        height, columns = self.stdscr.getmaxyx()
        if y < 0 or y >= height or x >= columns:
            return
        if width is not None:
            text = text[:width]
        text = text[:max(0, columns - x)]  # the bottom-right cell raises in curses; put() swallows it
        attr = self.pairs.get(style, 0) | (curses.A_BOLD if bold else 0)
        try:
            self.stdscr.addstr(y, x, text, attr)
        except curses.error:
            pass

    def bar(self, y, x, width, fraction, style='text'):
        filled = max(0, min(width, round(fraction * width)))
        self.put(y, x, '━' * filled, style)
        self.put(y, x + filled, '━' * (width - filled), 'track')

    def draw(self):
        import curses
        self.stdscr.erase()
        rows, columns = self.stdscr.getmaxyx()
        # The card fills the popup, so C-a $ is the same size as every other popup.
        width = columns
        left = 0
        height = rows
        inner = width - 4
        title, totals, limit_rows, note = self.providers[self.tab]
        # frame
        self.put(0, left, '╭' + '─' * (width - 2) + '╮', 'accent')
        for y in range(1, height - 1):
            self.put(y, left, '│', 'accent'); self.put(y, left + width - 1, '│', 'accent')
        self.put(height - 1, left, '╰' + '─' * (width - 2) + '╯', 'accent')
        x = left + 2
        y = 1
        # icon and title
        for line_index, line in enumerate(ICONS.get(title, ['', '', ''])):
            self.put(y + line_index, x, line, 'icon', bold=True)
        self.put(y, x + 10, title, 'text', bold=True)
        plan = totals.get('plan') or ''
        self.put(y + 1, x + 10, (plan.upper() + ' · ' if plan else '') + 'last %d days' % self.days, 'muted')
        y += 4
        # tabs
        tab_width = max(8, (inner - 2 * (len(self.providers) - 1)) // len(self.providers))
        for index, (name, *_) in enumerate(self.providers):
            label = name[:tab_width - 2].center(tab_width - 2)
            style = 'tab' if index == self.tab else 'muted'
            self.put(y, x + index * (tab_width + 2), '[' + label + ']' if index != self.tab else ' ' + label + ' ', style, bold=(index == self.tab))
        y += 2
        self.put(y, x, '─' * inner, 'track'); y += 1
        # limits
        self.put(y, x, 'LIMITS', 'muted', bold=True); y += 1
        if limit_rows:
            for label, used, resets in limit_rows:
                self.put(y, x, label[:1].upper() + label[1:], 'text', bold=True)
                self.put(y, x + inner - 5, f'{used:4.0f}%', 'text'); y += 1
                self.bar(y, x, inner, used / 100); y += 1
                self.put(y, x, resets_in(resets), 'muted'); y += 1
        else:
            self.put(y, x, note or 'no live window data', 'muted'); y += 1
        y += 1
        self.put(y, x, '─' * inner, 'track'); y += 1
        # tokens by day
        self.put(y, x, 'TOKENS BY DAY', 'muted', bold=True); y += 1
        today = date.today()
        day_keys = [(today - timedelta(days=offset)).isoformat() for offset in range(min(self.days, 7) - 1, -1, -1)]
        peak = max([totals['days'].get(day, 0) for day in day_keys] + [1])
        bar_x = x + 7
        bar_width = inner - 7 - 9
        for day in day_keys:
            tokens = totals['days'].get(day, 0)
            is_today = day == today.isoformat()
            name = 'Today' if is_today else date.fromisoformat(day).strftime('%a')
            self.put(y, x, name, 'text' if is_today else 'muted', bold=is_today)
            self.bar(y, bar_x, bar_width, tokens / peak)
            self.put(y, bar_x + bar_width + 1, f'{human(tokens):>7}', 'text'); y += 1
        if self.days > 7:
            self.put(y, x, f'{self.days} days', 'muted')
            self.put(y, bar_x + bar_width + 1, f'{human(sum(totals["days"].values())):>7}', 'muted', bold=True); y += 1
        y += 1
        self.put(y, x, '─' * inner, 'track'); y += 1
        # tokens by model
        self.put(y, x, 'TOKENS BY MODEL', 'muted', bold=True); y += 1
        models = sorted(totals['models'].items(), key=lambda item: -item[1])
        peak = max([tokens for _, tokens in models] + [1])
        if not models:
            self.put(y, x, 'nothing in the last %d days' % self.days, 'muted'); y += 1
        self.put(y - len(models) - 1 if models else y - 2, x + inner - 12, '', 'muted')
        for model, tokens in models:
            if y >= height - 2:
                break
            label = ' ' + pretty_model(model) + ' '
            filled = max(len(label), round(tokens / peak * (inner - 8)))
            self.put(y, x, label.ljust(filled), 'fill', bold=True)
            self.put(y, x + inner - 7, f'{human(tokens):>7}', 'text'); y += 1
        hint = 'Tab/←→ switch  r refresh  q close'
        self.put(height - 1, left + width - len(hint) - 3, ' ' + hint + ' ', 'muted')
        self.stdscr.refresh()

    def run(self):
        import curses
        curses.curs_set(0)
        self.stdscr.keypad(True)
        while True:
            self.draw()
            key = self.stdscr.getch()
            if key in (ord('q'), 27):
                return
            if ord('1') <= key <= ord('9'):
                self.tab = min(key - ord('1'), len(self.providers) - 1)
            elif key in (9, curses.KEY_RIGHT, ord('l')):
                self.tab = (self.tab + 1) % len(self.providers)
            elif key in (curses.KEY_BTAB, curses.KEY_LEFT, ord('h')):
                self.tab = (self.tab - 1) % len(self.providers)
            elif key == ord('r'):
                self.providers = self.refresh()
            elif key == curses.KEY_RESIZE:
                continue


def interactive(days, palette):
    import curses
    providers, _ = gather(days)
    refresh = lambda: gather(days)[0]  # noqa: E731
    curses.wrapper(lambda stdscr: Screen(stdscr, providers, days, palette, refresh).run())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--days', type=int, default=30, help='window for the totals; the day bars always show the last week')
    parser.add_argument('--width', type=int)
    parser.add_argument('--plain', action='store_true', help='no colors, no interface: print the report')
    parser.add_argument('--no-limits', action='store_true', help='skip the live quota lookup')
    parser.add_argument('--json', action='store_true', help='print the aggregates instead of the report')
    args = parser.parse_args(argv)
    if args.json:
        providers, windows = gather(args.days, limits=not args.no_limits)
        print(json.dumps({title: totals for title, totals, _, _ in providers} | {'windows': windows}, default=str, indent=1))
        return 0
    interactive_terminal = not args.plain and sys.stdin.isatty() and sys.stdout.isatty() and not args.no_limits
    palette = {}
    if not args.plain and sys.stdin.isatty():
        sys.path.insert(0, str(ROOT / 'scripts'))
        from appearance import current_theme
        palette = current_theme()[1]['colors']
    if interactive_terminal:
        interactive(args.days, palette)
        return 0
    providers, windows = gather(args.days, limits=not args.no_limits)
    width = args.width or shutil.get_terminal_size((100, 40)).columns
    sys.stdout.write(render(providers, windows, args.days, min(width - 2, 110), Painter(not args.plain and sys.stdin.isatty(), palette)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
