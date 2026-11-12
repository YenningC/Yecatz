"""Generate transparent color layers from the original pixel art; requires PySide6."""
from pathlib import Path
from PySide6.QtGui import QImage

root = Path(__file__).resolve().parent.parent
colors = {
    'suit': {'navy': (50, 70, 96), 'wine': (81, 48, 57), 'green': (49, 72, 61)},
    'tie': {'red': (174, 57, 65), 'blue': (66, 114, 164), 'gold': (188, 145, 60)},
}

for sprite in ('cat', 'cat-blink', 'cat-entry'):
    source = QImage(str(root / 'Assets' / (sprite + '.png'))).convertToFormat(QImage.Format.Format_RGBA8888)
    width, height = source.width(), source.height()
    data = bytes(source.constBits())
    outputs = {(part, name): bytearray(len(data)) for part, shades in colors.items() for name in shades}
    for y in range(height):
        yn = y / height
        if not (0.50 <= yn <= 0.90):
            continue
        for x in range(width):
            pos = (y * width + x) * 4
            r, g, b, a = data[pos:pos + 4]
            if a == 0:
                continue
            # The suit uses neutral dark pixels; retain its ink outlines and shirt.
            cell_x = (x % (width // 4)) / (width // 4) if sprite == 'cat-entry' else x / width
            if sprite == 'cat-entry':
                fourth = x // (width // 4) == 3
                tie_region = (0.39 < cell_x < 0.46 if fourth else 0.365 < cell_x < 0.43) and 0.515 < yn < 0.655
            else:
                tie_region = 0.469 < cell_x < 0.535 and 0.548 < yn < 0.69
            neutral = max(r, g, b) - min(r, g, b) <= 25
            part = None
            if tie_region and neutral and 59 <= (r + g + b) / 3 <= 207:
                part, base = 'tie', 165
            elif neutral and 29 <= (r + g + b) / 3 <= 83 and not tie_region and (sprite != 'cat-entry' or yn < 0.85):
                part, base = 'suit', 49
            if part:
                for name, target in colors[part].items():
                    layer = outputs[(part, name)]
                    for channel, original in enumerate((r, g, b)):
                        layer[pos + channel] = max(0, min(255, round(original * target[channel] / base)))
                    layer[pos + 3] = a
    for (part, name), pixels in outputs.items():
        image = QImage(bytes(pixels), width, height, width * 4, QImage.Format.Format_RGBA8888)
        assert image.save(str(root / 'Assets' / 'Wardrobe' / f'{sprite}-{part}-{name}.png'))
    print(sprite, 'done')
