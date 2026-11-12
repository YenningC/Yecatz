"""Draw Yecatz's small pixel accessories as transparent layers. Requires PySide6."""
from pathlib import Path
from PySide6.QtCore import QPoint, Qt
from PySide6.QtGui import QColor, QImage, QPainter, QPolygon

root = Path(__file__).resolve().parent.parent
variants = ('scarf-wine', 'scarf-cream', 'bow-black', 'bow-red', 'pocket-white', 'pocket-red')


def paint(p, kind, cx, pocket_x, y):
    def rect(color, x, top, w, h):
        p.fillRect(x, top, w, h, QColor(color))
    def poly(color, points):
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(color))
        p.drawPolygon(QPolygon([QPoint(x, yy) for x, yy in points]))
    ink = '#181419'
    if kind.startswith('scarf-'):
        base, light, shadow = (('#793641', '#a9565b', '#50272e') if kind.endswith('wine')
                               else ('#d3b58c', '#e7d4b0', '#a98662'))
        # Short pixel scarf wraps around the collar, leaving the face untouched.
        rect(ink, cx-25, y, 50, 9)
        rect(base, cx-23, y+2, 46, 5)
        rect(light, cx-21, y+2, 32, 2)
        rect(ink, cx+10, y+6, 11, 22)
        rect(base, cx+12, y+8, 7, 17)
        rect(shadow, cx+12, y+22, 7, 3)
        rect(light, cx+13, y+9, 2, 11)
        rect(ink, cx+11, y+27, 2, 2)
        rect(ink, cx+16, y+27, 2, 2)
    elif kind.startswith('bow-'):
        # Replace the long tie with a narrow white shirt and place the bow on top.
        poly(ink, [(cx-7,y+1),(cx+7,y+1),(cx+7,y+26),(cx,y+38),(cx-7,y+26)])
        poly('#f5e9e5', [(cx-5,y+3),(cx+5,y+3),(cx+5,y+24),(cx,y+32),(cx-5,y+24)])
        base, light = (('#39383d', '#68666b') if kind.endswith('black') else ('#843740', '#b25960'))
        poly(ink, [(cx-14,y+3),(cx-3,y+7),(cx+3,y+7),(cx+14,y+3),(cx+14,y+15),(cx+3,y+12),(cx-3,y+12),(cx-14,y+15)])
        poly(base, [(cx-12,y+5),(cx-3,y+8),(cx-3,y+11),(cx-12,y+13)])
        poly(base, [(cx+12,y+5),(cx+3,y+8),(cx+3,y+11),(cx+12,y+13)])
        rect(light, cx-2, y+7, 4, 5)
    elif kind.startswith('pocket-'):
        fill = '#f5ece4' if kind.endswith('white') else '#a54c51'
        rect(ink, pocket_x-1, y+1, 12, 7)
        rect(fill, pocket_x, y+2, 10, 3)
        rect(fill, pocket_x+2, y, 3, 2)
        rect(fill, pocket_x+6, y+1, 3, 2)

for sprite in ('cat', 'cat-blink', 'cat-entry'):
    original = QImage(str(root/'Assets'/f'{sprite}.png'))
    entry = sprite == 'cat-entry'
    for variant in variants:
        canvas = QImage(720 if entry else 180, 220, QImage.Format.Format_RGBA8888)
        canvas.fill(Qt.GlobalColor.transparent)
        painter = QPainter(canvas)
        if entry:
            for index in range(4):
                painter.save(); painter.translate(index * 180, 0)
                # The side and front walk frames have their own smaller silhouettes.
                center = 74 if index < 3 else 80
                if variant.startswith('scarf-'):
                    painter.translate(center, 0); painter.scale(0.72, 1); painter.translate(-center, 0)
                paint(painter, variant, center, 87 if index < 3 else 94,
                      115 if not variant.startswith('pocket-') else 151)
                painter.restore()
        else:
            paint(painter, variant, 90, 108, 115 if not variant.startswith('pocket-') else 156)
        painter.end()
        layer = canvas.scaled(original.width(), original.height(), Qt.AspectRatioMode.IgnoreAspectRatio,
                              Qt.TransformationMode.FastTransformation)
        assert layer.save(str(root/'Assets'/'Wardrobe'/f'{sprite}-accessory-{variant}.png'))
    print(sprite, 'accessories done')
