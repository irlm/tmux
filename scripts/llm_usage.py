#!/usr/bin/env python3
"""Show what the coding agents on this machine have consumed.

Claude Code and Codex keep a transcript per session with the token usage of
every reply. This reads the transcripts touched in the last week (cached per
file, so a popup costs a few milliseconds after the first run), adds the
live rate-limit windows from quota-axi when it is installed, and draws:

    LIMITS           remaining window budget and when it resets
    TOKENS BY DAY    last seven days, today last
    TOKENS BY MODEL  which models the tokens went to
"""
import argparse
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CACHE_DIR = Path(os.environ.get('TMUX_CACHE_DIR', str(Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'tmux')))
RESET = '\033[0m'
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
    """Live windows from quota-axi: {provider: ([(label, used%, resets_at)], note)}."""
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
        for window in entry.get('windows') or []:
            remaining = window.get('percentRemaining')
            if remaining is None:
                continue
            rows.append((window.get('label') or window.get('id') or 'window', 100 - float(remaining), window.get('resetsAt')))
        state = entry.get('state') or {}
        note = ''
        if state.get('status') == 'auth_required':
            note = 'run once: ' + (state.get('remedyCommand') or 'quota-axi --allow-keychain-prompt')
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
    label_width = 12
    lines = []
    today = date.today()
    day_keys = [(today - timedelta(days=offset)).isoformat() for offset in range(days - 1, -1, -1)]
    for title, totals, limit_rows, note in providers:
        lines.append(painter.paint(title, 'accent', True))
        lines.append('')
        lines.append(painter.paint('LIMITS', 'muted', True))
        if limit_rows:
            for label, used, resets in limit_rows:
                lines.append(f'  {label.capitalize():<{label_width}} {painter.bar(used / 100, width - label_width - 12)} {used:5.1f}%')
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


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--days', type=int, default=7)
    parser.add_argument('--width', type=int)
    parser.add_argument('--plain', action='store_true', help='no colors')
    parser.add_argument('--no-limits', action='store_true', help='skip the live quota lookup')
    parser.add_argument('--json', action='store_true', help='print the aggregates instead of the report')
    args = parser.parse_args(argv)
    since = (datetime.now() - timedelta(days=args.days + 1)).timestamp()
    cache = Cache(CACHE_DIR / 'llm-usage.json')
    claude_dir = Path(os.environ.get('CLAUDE_CONFIG_DIR', str(Path.home() / '.claude'))) / 'projects'
    codex_dir = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))) / 'sessions'
    claude = collect('claude', claude_dir, '*.jsonl', parse_claude, since, cache)
    codex = collect('codex', codex_dir, '*.jsonl', parse_codex, since, cache)
    windows = {} if args.no_limits else quota_windows()
    if args.json:
        print(json.dumps({'claude': {k: v for k, v in claude.items() if k != 'limits'},
                          'codex': {k: v for k, v in codex.items()}, 'windows': windows}, default=str, indent=1))
        return 0
    claude_rows, claude_note = windows.get('claude', ([], 'quota-axi not installed' if not shutil.which('quota-axi') else ''))
    codex_rows, codex_note = windows.get('codex', ([], ''))
    codex_rows = codex_rows or codex_windows(codex.get('limits'))
    providers = [('Claude Code', claude, claude_rows, claude_note), ('Codex', codex, codex_rows, codex_note)]
    colored = not args.plain and sys.stdin.isatty()
    palette = {}
    if colored:
        sys.path.insert(0, str(ROOT / 'scripts'))
        from appearance import current_theme
        palette = current_theme()[1]['colors']
    width = args.width or shutil.get_terminal_size((100, 40)).columns
    sys.stdout.write(render(providers, windows, args.days, min(width - 2, 110), Painter(colored, palette)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
