#!/usr/bin/env python3
"""Best-effort SSH destination detection from a single process-table snapshot."""
import os
import shlex
import subprocess
import sys

CLIENTS = {'ssh', 'slogin', 'mosh', 'mosh-client', 'autossh', 'et', 'tsh'}
VALUE_FLAGS = set('iopFJLRDwWeEbcSmBOP')


def destination(command):
    try:
        args = shlex.split(command)
    except ValueError:
        return ''
    if not args or os.path.basename(args[0]) not in CLIENTS:
        return ''
    program = os.path.basename(args.pop(0))
    if program == 'tsh' and args[:1] == ['ssh']:
        args.pop(0)
    user = port = ''
    while args:
        arg = args.pop(0)
        if arg in ('-p', '-l'):
            value = args.pop(0) if args else ''
            if arg == '-p': port = value
            else: user = value
        elif arg.startswith('-p'):
            port = arg[2:]
        elif arg.startswith('-l'):
            user = arg[2:]
        elif len(arg) == 2 and arg[0] == '-' and arg[1] in VALUE_FLAGS:
            if args: args.pop(0)
        elif arg == '--':
            break
        elif arg.startswith('-'):
            continue
        else:
            args.insert(0, arg)
            break
    if not args:
        return ''
    target = args[0]
    if '@' in target:
        user, target = target.rsplit('@', 1)
    def safe(value):
        return ''.join(c for c in value if c.isprintable()).replace('#', '##')[:120]
    out = f'#[fg=colour2,bold] SSH #[fg=colour4]{safe(target)}#[default]'
    if user: out += f' as {safe(user)}'
    if port: out += f':{safe(port)}'
    return out


def find_remote(pid, snapshot):
    children = {}
    commands = {}
    for line in snapshot.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) != 3:
            continue
        child, parent, command = fields
        children.setdefault(parent, []).append(child)
        commands[child] = command
    pending = [str(pid)]
    for _ in range(3):
        for child in pending:
            result = destination(commands.get(child, ''))
            if result:
                return result
        pending = [child for parent in pending for child in children.get(parent, [])]
    return ''


if __name__ == '__main__':
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        sys.exit(1)
    snapshot = subprocess.run(['ps', '-axo', 'pid=,ppid=,command='],
                              capture_output=True, text=True, check=False)
    print(find_remote(sys.argv[1], snapshot.stdout))
