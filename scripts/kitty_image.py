#!/usr/bin/env python3
"""Draw a PNG at the cursor with the Kitty graphics protocol.

    kitty_image.py <file.png> [columns] [rows]

The PNG bytes travel inside the escape sequence (direct transmission), so no
decoder is needed on this side: the terminal, or Herdr passing it on to the
terminal, does the work. Nothing is printed when the file is missing.
"""
import base64
import sys


def main(argv):
    if len(argv) < 2:
        return 2
    try:
        with open(argv[1], 'rb') as stream:
            data = base64.standard_b64encode(stream.read())
    except OSError:
        return 0
    columns = int(argv[2]) if len(argv) > 2 else 28
    rows = int(argv[3]) if len(argv) > 3 else 14
    out = sys.stdout.buffer
    chunk = 4096
    first = True
    for start in range(0, len(data), chunk):
        piece = data[start:start + chunk]
        more = 1 if start + chunk < len(data) else 0
        control = (f'a=T,f=100,q=2,c={columns},r={rows},m={more}' if first else f'm={more}').encode()
        out.write(b'\033_G' + control + b';' + piece + b'\033\\')
        first = False
    out.flush()
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
