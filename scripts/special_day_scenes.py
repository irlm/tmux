"""Small, finite ASCII scenes. Loaded only while a celebration is playing."""
import math

FPS = 12
FRAME_COUNT = 48
MAX_WIDTH = 96
MAX_HEIGHT = 16
DIRECTIONS = tuple((math.cos(n * math.pi / 8), math.sin(n * math.pi / 8))
                   for n in range(16))
SWAY = (0, 0, 1, 1, 0, 0, -1, -1)


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


def fireworks_frame(width, height, frame):
    canvas = Canvas(width, height)
    rockets = ((.17, .28, 0), (.73, .35, 6), (.45, .2, 14),
               (.85, .45, 22), (.28, .25, 28))
    for fx, fy, launch in rockets:
        age = frame - launch
        if not 0 <= age < 25:
            continue
        x, y = round((width - 1) * fx), round((height - 1) * fy)
        if age < 6:
            rocket_y = height - 1 - round((height - 1 - y) * age / 5)
            canvas.put(x, rocket_y, '^')
            canvas.put(x, rocket_y + 1, '|')
            canvas.put(x, rocket_y + 2, ':')
            continue
        burst = age - 6
        radius = 1 + burst * .62
        fall = round(burst * burst * .018)
        glyph = '*' if burst < 8 else '+' if burst < 13 else '.'
        for dx, dy in DIRECTIONS:
            canvas.put(round(x + radius * 1.8 * dx), round(y + radius * dy + fall), glyph)
            if 3 <= burst < 13:
                canvas.put(round(x + (radius - 1.4) * 1.8 * dx),
                           round(y + (radius - 1.4) * dy + fall), '.')
        if burst < 3:
            canvas.put(x, y, '+')
    return canvas.lines()


def scene_frame(identifier, art, width, height, frame, fireworks=False):
    if fireworks:
        return fireworks_frame(width, height, frame)

    canvas = Canvas(width, height)
    sprite = art.splitlines()
    x = (width - max(map(len, sprite))) // 2
    y = max(0, (height - len(sprite)) // 2)
    sway = SWAY[(frame // 3) % len(SWAY)]

    if identifier == 'halloween':
        # A candle flicker and two bats crossing above the pumpkin.
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
