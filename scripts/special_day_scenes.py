"""Small, finite ASCII scenes. Loaded only while a celebration is playing."""
import math
from functools import lru_cache

FPS = 12
FRAME_COUNT = 48
MAX_WIDTH = 96
MAX_HEIGHT = 16
DIRECTIONS = tuple((math.cos(n * math.pi / 8), math.sin(n * math.pi / 8))
                   for n in range(16))
WILLOW = tuple((math.cos(n * math.pi / 15), -math.sin(n * math.pi / 15))
               for n in range(16))
HEART = tuple((math.sin(t) ** 3,
               -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) / 16)
              for t in (n * math.pi / 12 for n in range(24)))
BURSTS = (DIRECTIONS, WILLOW, HEART)
SWAY = (0, 0, 1, 1, 0, 0, -1, -1)
LETTERS = {
    'U': ('*   *', '*   *', '*   *', '*   *', ' *** '),
    'S': (' ****', '*    ', ' *** ', '    *', '**** '),
    'A': (' *** ', '*   *', '*****', '*   *', '*   *'),
    '0': (' *** ', '*   *', '*   *', '*   *', ' *** '),
    '1': ('  *  ', ' **  ', '  *  ', '  *  ', ' *** '),
    '2': ('**** ', '    *', ' *** ', '*    ', '*****'),
    '3': ('**** ', '    *', ' *** ', '    *', '**** '),
    '4': ('*  * ', '*  * ', '*****', '   * ', '   * '),
    '5': ('*****', '*    ', '**** ', '    *', '**** '),
    '6': (' *** ', '*    ', '**** ', '*   *', ' *** '),
    '7': ('*****', '    *', '   * ', '  *  ', ' *   '),
    '8': (' *** ', '*   *', ' *** ', '*   *', ' *** '),
    '9': (' *** ', '*   *', ' ****', '    *', ' *** '),
}


@lru_cache(maxsize=32)
def banner_rows(text, width=MAX_WIDTH, height=MAX_HEIGHT):
    """A tiny built-in font; narrow or short terminals keep readable text."""
    rows = tuple('  '.join(LETTERS[char][row] for char in text) for row in range(5))
    if len(rows[0]) > width or height < len(rows):
        return (('U S A' if text == 'USA' else text)[:width],)
    return rows


@lru_cache(maxsize=32)
def letter_targets(text, width, height):
    """Cache the spark destinations for each letter or digit."""
    rows = banner_rows(text, width, height)
    left = (width - len(rows[0])) // 2
    top = (height - len(rows)) // 2
    if len(rows) == 1:
        return tuple(((left + x, top, char),) for x, char in enumerate(rows[0]) if char != ' ')
    return tuple(tuple((left + index * 7 + x, top + y, char)
                       for y, row in enumerate(LETTERS[letter])
                       for x, char in enumerate(row) if char != ' ')
                 for index, letter in enumerate(text))


class Canvas:
    def __init__(self, width, height):
        self.width, self.height = width, height
        self.rows = [[' '] * width for _ in range(height)]

    def put(self, x, y, text):
        if 0 <= y < self.height:
            for offset, char in enumerate(text):
                if 0 <= x + offset < self.width:
                    self.rows[y][x + offset] = char

    def sprite(self, x, y, lines):
        for offset, line in enumerate(lines):
            self.put(x, y + offset, line)

    def lines(self):
        # Preserve the canvas width so centering cannot shift moving particles.
        return [''.join(row) for row in self.rows]


def lettering_frame(width, height, frame, variation, text):
    """Launch each glyph, burst its sparks, and settle them into the full word."""
    canvas = Canvas(width, height)
    for index, targets in enumerate(letter_targets(text, width, height)):
        age = frame - index * 6
        if age < 0:
            continue
        cx = (min(x for x, _, _ in targets) + max(x for x, _, _ in targets)) / 2
        cy = (min(y for _, y, _ in targets) + max(y for _, y, _ in targets)) / 2
        if age < 6:
            launch_x = max(0, min(width - 1, cx + ((variation >> (index * 2)) % 9 - 4) * 2))
            progress = age / 5
            x = round(launch_x + (cx - launch_x) * progress)
            y = round(height - 1 + (cy - height + 1) * progress)
            canvas.put(x, y, '^')
            canvas.put(x, y + 1, '|')
            canvas.put(x, y + 2, ':')
            continue
        burst = age - 6
        directions = BURSTS[(variation + index) % len(BURSTS)]
        if burst < 3:
            radius = 1 + burst * .9
            for dx, dy in directions:
                canvas.put(round(cx + dx * radius * 1.6), round(cy + dy * radius), '+')
        elif burst < 12:
            progress = (burst - 3) / 9
            ease = progress * progress * (3 - 2 * progress)
            for spark, (target_x, target_y, _) in enumerate(targets):
                dx, dy = directions[(spark + variation) % len(directions)]
                origin_x, origin_y = cx + dx * 4.5, cy + dy * 3
                x = round(origin_x + (target_x - origin_x) * ease)
                y = round(origin_y + (target_y - origin_y) * ease + 4 * progress * (1 - progress))
                canvas.put(x, y + 1, '.')
                canvas.put(x, y, '*')
        else:
            for x, y, char in targets:
                canvas.put(x, y, char)
    return canvas.lines()


def fireworks_frame(width, height, frame, variation=0, banner=''):
    if banner:
        return lettering_frame(width, height, frame, variation, banner)
    canvas = Canvas(width, height)
    rockets = ((.17, .28, 0), (.73, .35, 6), (.45, .2, 14),
               (.85, .45, 22), (.28, .25, 28))
    for index, (fx, fy, launch) in enumerate(rockets):
        age = frame - launch
        if not 0 <= age < 25:
            continue
        fx = max(.08, min(.92, fx + ((variation >> (index * 2)) % 7 - 3) * .012))
        x, y = round((width - 1) * fx), round((height - 1) * fy)
        style = (variation + index) % len(BURSTS)
        if style == 2:
            y = max(y, round((height - 1) * .42))
        if age < 6:
            rocket_y = height - 1 - round((height - 1 - y) * age / 5)
            canvas.put(x, rocket_y, '^')
            canvas.put(x, rocket_y + 1, '|')
            canvas.put(x, rocket_y + 2, ':')
            continue
        burst = age - 6
        radius = 1 + burst * .62
        if style == 2:
            radius = min(radius, max(1, height * .35))
        fall = round(burst * burst * (.035 if style == 1 else .018))
        if style == 2:
            fall = 0
        glyph = '*' if burst < 8 else '+' if burst < 13 else '.'
        for dx, dy in BURSTS[style]:
            canvas.put(round(x + radius * 1.8 * dx), round(y + radius * dy + fall), glyph)
            if 3 <= burst < 13:
                canvas.put(round(x + (radius - 1.4) * 1.8 * dx),
                           round(y + (radius - 1.4) * dy + fall), '.')
        if burst < 3:
            canvas.put(x, y, '+')
    return canvas.lines()


def scene_frame(identifier, art, width, height, frame, fireworks=False, variation=0, banner=''):
    if fireworks:
        return fireworks_frame(width, height, frame, variation, banner)

    frame += variation
    canvas = Canvas(width, height)
    sprite = art.splitlines()
    x = (width - max(map(len, sprite))) // 2
    y = max(0, (height - len(sprite)) // 2)
    sway = SWAY[(frame // 3) % len(SWAY)]

    if identifier == 'halloween':
        # A candle, crossing bats, and a little ghost that floats beside them.
        if width >= 42:
            ghost_x = x + 14 if variation % 2 else x - 12
            ghost_x = max(0, min(width - 5, ghost_x))
            canvas.sprite(ghost_x, max(0, y + sway), [' .-. ', '(o o)', '| O |', "'~~~'"])
        if frame % 14 in (8, 9):
            sprite = [line.replace('^', 'o') for line in sprite]
        canvas.sprite(x, min(y + 1, max(0, height - len(sprite))), sprite)
        wings = ('\\^v^/', '-^v^-', '/^v^\\')[(frame // 2) % 3]
        canvas.put((frame * 2) % (width + 7) - 6, max(0, y - 2 + sway), wings)
        canvas.put(width - (frame * 2 + width // 2) % (width + 7), 0, wings)
    elif identifier == 'christmas':
        for flake in range(14):
            canvas.put((flake * 13 + frame // 6) % width,
                       (frame // 3 + flake * 7) % height, '.' if flake % 3 else '*')
        canvas.sprite(x, y, sprite)
        canvas.put(x + 4, y, '*' if frame % 8 < 4 else '+')
        if frame % 12 < 6:
            canvas.put(x + 3, y + 2, 'o')
            canvas.put(x + 4, y + 3, 'o')
        star = frame % 36
        if star < 14:
            canvas.put(round((width + 5) * star / 13) - 5, 0, '--*')
    elif identifier == 'valentine':
        for heart in range(5):
            canvas.put((heart * 17 + sway) % width,
                       height - 1 - (frame // 2 + heart * 3) % height, '<3')
        canvas.sprite(x + sway, y, sprite)
    elif identifier == 'st-patrick':
        for coin in range(7):
            canvas.put((coin * 19 + frame // 4) % width,
                       (frame // 3 + coin * 5) % height, 'o' if (frame + coin) % 6 < 3 else '+')
        canvas.sprite(x + sway, y, sprite)
    elif identifier == 'thanksgiving':
        for leaf in range(7):
            canvas.put((leaf * 17 + frame // 4) % width,
                       (frame // 4 + leaf * 5) % height, '/' if frame % 8 < 4 else '\\')
        sprite[-1] = '  / \\' if frame % 8 < 4 else '  \\ /'
        canvas.sprite(x + sway * 2, y, sprite)
    else:
        canvas.sprite(x, y, sprite)
    return canvas.lines()
