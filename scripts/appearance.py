#!/usr/bin/env python3
"""Shared theme selection for tmux, popup tools, and managed shell prompts."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COLORS = ('background', 'selection', 'foreground', 'muted', 'accent', 'blue',
          'cyan', 'green', 'yellow', 'red', 'magenta')


def theme_dir():
    return Path(os.environ.get('TMUX_THEME_DIR', str(Path.home() / '.config/tmux-user')))


def catalog(root=ROOT):
    themes = json.loads((root / 'themes.json').read_text())
    for identifier, theme in themes.items():
        if not re.fullmatch(r'[a-z][a-z0-9-]*', identifier):
            raise ValueError('Invalid theme identifier')
        if any(not re.fullmatch(r'#[0-9a-fA-F]{6}', theme['colors'][role]) for role in COLORS):
            raise ValueError(f'Invalid colors in {identifier}')
        if theme['prompt'] not in ('nord.omp.json', 'catppuccin.omp.json'):
            raise ValueError('Invalid prompt source')
    return themes


def current_theme(root=ROOT, directory=None):
    themes = catalog(root)
    try:
        identifier = ((directory or theme_dir()) / 'theme').read_text().strip()
    except OSError:
        identifier = 'nord'
    if identifier not in themes:
        identifier = 'nord'
    return identifier, themes[identifier]


def private_directory(directory):
    if directory.is_symlink():
        raise ValueError(f'Theme directory must not be a symlink: {directory}')
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Windows has no numeric owner to compare and ignores Unix modes.
    if hasattr(os, 'getuid') and directory.stat().st_uid != os.getuid():
        raise ValueError('Theme directory belongs to another user')
    directory.chmod(0o700)


def atomic_write(path, content):
    handle, name = tempfile.mkstemp(prefix='.theme-', dir=path.parent)
    try:
        with os.fdopen(handle, 'w') as stream:
            stream.write(content)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def lazygit_pager():
    """delta gives lazygit's diff pane syntax colours and line numbers (git-delta);
    without it lazygit keeps git's own colouring."""
    if not shutil.which('delta'):
        return {}
    return {'git': {'paging': {'colorArg': 'always', 'pager': 'delta --dark --paging=never --line-numbers --syntax-theme Nord'}}}


def lazygit_theme(theme):
    c = theme['colors']
    styles = {
        'activeBorderColor': [c['accent'], 'bold'],
        'inactiveBorderColor': [c['muted']],
        'searchingActiveBorderColor': [c['yellow'], 'bold'],
        'optionsTextColor': [c['blue']],
        'selectedLineFgColor': ['bold'],
        'selectedLineBgColor': [c['selection']],
        'inactiveViewSelectedLineBgColor': [c['selection']],
        'unstagedChangesColor': [c['red'], 'bold'],
        'defaultFgColor': [c['foreground']],
        'cherryPickedCommitFgColor': [c['background']],
        'cherryPickedCommitBgColor': [c['cyan']],
        'markedBaseCommitFgColor': [c['background']],
        'markedBaseCommitBgColor': [c['yellow']],
    }
    return {'gui': {'colorScheme': 'dark', 'theme': styles, 'darkTheme': styles}}


def fzf_colors(theme):
    c = theme['colors']
    return '--color=' + ','.join(f'{role}:{value}' for role, value in {
        'fg': c['foreground'], 'bg': c['background'], 'hl': c['accent'],
        'fg+': c['foreground'], 'bg+': c['selection'], 'hl+': c['accent'],
        'info': c['yellow'], 'prompt': c['accent'], 'pointer': c['yellow'],
        'marker': c['green'], 'spinner': c['accent'], 'header': c['muted'],
    }.items())


def fzf_options(theme, existing=''):
    options = shlex.split(existing)
    kept = []
    skip = False
    for option in options:
        if skip:
            skip = False
        elif option == '--color':
            skip = True
        elif not option.startswith('--color='):
            kept.append(option)
    return ' '.join(part for part in (shlex.join(kept), fzf_colors(theme)) if part)


def prompt_theme(theme, root=ROOT):
    c = theme['colors']
    text = (root / theme['prompt']).read_text()
    replacements = {
        '#2e3440': c['background'], '#24273a': c['background'], '#1e2030': c['background'],
        '#d8dee9': c['foreground'], '#eceff4': c['foreground'], '#cad3f5': c['foreground'],
        '#4c566a': c['muted'], '#6e738d': c['muted'],
        '#81a1c1': c['blue'], '#5e81ac': c['blue'], '#8aadf4': c['blue'],
        '#88c0d0': c['accent'], '#8bd5ca': c['accent'],
        '#a3be8c': c['green'], '#a6da95': c['green'],
        '#ebcb8b': c['yellow'], '#eed49f': c['yellow'],
        '#bf616a': c['red'], '#ed8796': c['red'], '#c6a0f6': c['magenta'],
    }
    text = re.sub(r'#[0-9a-fA-F]{6}', lambda match: replacements.get(match[0].lower(), match[0]), text)
    return json.loads(text)


def write_outputs(theme, directory=None, root=ROOT):
    directory = directory or theme_dir()
    private_directory(directory)
    atomic_write(directory / 'lazygit.yml', json.dumps({**lazygit_theme(theme), **lazygit_pager()}, indent=2) + '\n')
    atomic_write(directory / 'prompt.omp.json', json.dumps(prompt_theme(theme, root), indent=2) + '\n')
    atomic_write(directory / 'fzf.opts', fzf_colors(theme) + '\n')


def apply_tmux(identifier, theme):
    if not shutil.which('tmux'):
        return False
    # list-sessions never starts a server. A saved theme also works outside tmux.
    if subprocess.run(['tmux', 'list-sessions'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        return False
    c = theme['colors']
    options = {
        'status-style': f"fg={c['foreground']},bg={c['background']}",
        'message-style': f"fg={c['foreground']},bg={c['selection']}",
        'message-command-style': f"fg={c['foreground']},bg={c['selection']}",
        'mode-style': f"fg={c['foreground']},bg={c['selection']}",
        'pane-border-style': f"fg={c['muted']}",
        'pane-active-border-style': f"fg={c['accent']}",
        'window-style': f"fg={c['foreground']},bg={c['background']}",
        'window-active-style': f"fg={c['foreground']},bg={c['background']}",
        'popup-style': f"fg={c['foreground']},bg={c['background']}",
        'popup-border-style': f"fg={c['accent']}",
        'window-status-style': f"fg={c['muted']},bg={c['background']}",
        'window-status-current-style': f"fg={c['accent']},bg={c['selection']},bold",
        'window-status-activity-style': f"fg={c['yellow']},italics",
        'window-status-bell-style': f"fg={c['red']},bold",
        'clock-mode-colour': c['accent'], '@theme': identifier,
    }
    options.update({'@theme_' + role: value for role, value in c.items()})
    supports_palette = subprocess.run(['tmux', 'show-options', '-g', 'pane-colours'],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if supports_palette:
        palette = [c['background'], c['red'], c['green'], c['yellow'], c['blue'], c['magenta'],
                   c['cyan'], c['foreground'], c['muted'], c['red'], c['green'], c['yellow'],
                   c['blue'], c['magenta'], c['accent'], c['foreground']]
        options.update({f'pane-colours[{index}]': value for index, value in enumerate(palette)})
    command = ['tmux']
    for option, value in options.items():
        if len(command) > 1:
            command.append(';')
        command.extend(['set-option', '-g', option, value])
    subprocess.run(command, check=True)
    # A server can restore its theme before its first client attaches.
    subprocess.run(['tmux', 'refresh-client', '-S'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    previous = subprocess.run(['tmux', 'show-environment', '-g', 'FZF_DEFAULT_OPTS'],
                              capture_output=True, text=True)
    existing = previous.stdout.partition('=')[2].rstrip('\n') if previous.returncode == 0 else os.environ.get('FZF_DEFAULT_OPTS', '')
    subprocess.run(['tmux', 'set-environment', '-g', 'FZF_DEFAULT_OPTS', fzf_options(theme, existing)], check=True)
    if (theme_dir() / 'lazygit.yml').is_file():
        base = lazygit_config_files()
        subprocess.run(['tmux', 'set-environment', '-g', 'LG_CONFIG_FILE', base], check=True)
    return True


def select_theme(identifier, root=ROOT, directory=None):
    themes = catalog(root)
    if identifier not in themes:
        raise ValueError(f'Unknown theme: {identifier}')
    theme = themes[identifier]
    directory = directory or theme_dir()
    write_outputs(theme, directory, root)
    atomic_write(directory / 'theme', identifier + '\n')
    apply_tmux(identifier, theme)
    apply_herdr(directory, root)
    return theme


def apply_herdr(directory, root=ROOT):
    """A pick here wins over a pick in Herdr's settings: forget that one and
    re-render the Herdr config so its theme follows this palette."""
    options = directory / 'options.env'
    if options.is_file():
        kept = [line for line in options.read_text().splitlines() if not line.startswith('herdr_theme=')]
        atomic_write(options, ''.join(line + '\n' for line in kept))
    renderer = root / 'scripts' / 'herdr-config.sh'
    if not shutil.which('herdr') or not renderer.is_file():
        return False
    managed = Path(os.environ.get('HERDR_CONFIG_PATH', str(Path.home() / '.config/herdr/config.toml')))
    try:
        if '# Generated by irlm/tmux' not in managed.read_text()[:400]:
            return False
    except OSError:
        return False
    return subprocess.run(['bash', str(renderer)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def git_color_environment(theme, environment=None):
    env = dict(os.environ if environment is None else environment)
    existing = env.get('GIT_CONFIG_COUNT', '0')
    if not re.fullmatch(r'[0-9]{1,4}', existing):
        raise ValueError('Invalid GIT_CONFIG_COUNT')
    count = int(existing)
    c = theme['colors']
    settings = {'color.diff.old': c['red'], 'color.diff.new': c['green'],
                'color.diff.meta': c['blue'] + ' bold', 'color.diff.frag': c['cyan'] + ' bold',
                'color.diff.commit': c['yellow'], 'color.status.changed': c['red'],
                'color.status.untracked': c['red'], 'color.status.added': c['green']}
    for key, value in settings.items():
        env[f'GIT_CONFIG_KEY_{count}'] = key
        env[f'GIT_CONFIG_VALUE_{count}'] = value
        count += 1
    env['GIT_CONFIG_COUNT'] = str(count)
    return env


def lazygit_config_files(base=None, directory=None):
    base = os.environ.get('LG_CONFIG_FILE', '') if base is None else base
    if not base:
        if shutil.which('lazygit'):
            result = subprocess.run(['lazygit', '--print-config-dir'], capture_output=True, text=True, check=True)
            candidate = Path(result.stdout.strip()) / 'config.yml'
            if candidate.is_file():
                base = str(candidate)
    overlay = str((directory or theme_dir()) / 'lazygit.yml')
    configs = [path for path in base.split(',') if path and path != overlay]
    configs.append(overlay)
    return ','.join(configs)


def launch_lazygit(arguments):
    _, theme = current_theme()
    write_outputs(theme)
    # Merge explicit config files too; the theme only overrides appearance.
    forwarded = []
    base = None
    arguments = iter(arguments)
    for argument in arguments:
        if argument in ('--use-config-file', '-ucf'):
            base = next(arguments, None)
            if base is None:
                raise ValueError('--use-config-file requires a path')
        elif argument.startswith(('--use-config-file=', '-ucf=')):
            base = argument.partition('=')[2]
        else:
            forwarded.append(argument)
    env = git_color_environment(theme)
    env['LG_CONFIG_FILE'] = lazygit_config_files(base=base)
    os.execvpe('lazygit', ['lazygit', *forwarded], env)


def preview(identifier):
    theme = catalog()[identifier]
    c = theme['colors']
    def sample(role, text, background='background'):
        def rgb(value):
            return ';'.join(str(int(value[index:index + 2], 16)) for index in (1, 3, 5))
        print(f"\033[48;2;{rgb(c[background])}m\033[38;2;{rgb(c[role])}m {text} \033[0m")
    print(theme['name'] + '\n' + theme['description'] + '\n')
    sample('foreground', 'Normal text')
    sample('red', ' M  unstaged-file.py / removed diff line')
    sample('red', ' M  selected-file.py', 'selection')
    sample('green', ' A  staged-file.py / added diff line')
    sample('yellow', 'Warning / changed state')
    sample('accent', 'Active border / focused control')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('list', 'current', 'apply', 'restore', 'preview', 'lazygit'))
    parser.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    try:
        if args.command == 'list':
            selected, _ = current_theme()
            for identifier, theme in catalog().items():
                suffix = ' (current)' if identifier == selected else ''
                print(f"{identifier}\t{theme['name']}{suffix}\t{theme['description']}")
        elif args.command == 'current':
            print(current_theme()[0])
        elif args.command == 'restore':
            identifier, theme = current_theme()
            if (theme_dir() / 'theme').is_file():
                write_outputs(theme)
            apply_tmux(identifier, theme)
        elif args.command == 'lazygit':
            launch_lazygit(args.arguments)
        else:
            if len(args.arguments) != 1:
                parser.error('a theme identifier is required')
            if args.command == 'preview':
                preview(args.arguments[0])
            else:
                theme = select_theme(args.arguments[0])
                print(f"Applied {theme['name']}. Reopen tool popups; shell prompts use the choice in new shells.")
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f'Theme change failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
