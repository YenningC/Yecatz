"""Draw the hidden outfit as separate transparent pixel layers. Requires PySide6."""
from pathlib import Path
from PySide6.QtCore import QPoint, Qt
from PySide6.QtGui import QColor, QImage, QPainter, QPolygon

root = Path(__file__).resolve().parent.parent
out = root / 'Assets' / 'Easter'
out.mkdir(parents=True, exist_ok=True)

def create(name, fn):
    image = QImage(180, 220, QImage.Format.Format_RGBA8888)
    image.fill(Qt.GlobalColor.transparent)
    p = QPainter(image)
    p.setRenderHint(QPainter.RenderHint.Antialiasing, False)
    fn(p)
    p.end()
    assert image.save(str(out / f'{name}.png'))

def rect(p, color, x, y, w, h):
    p.fillRect(x, y, w, h, QColor(color))

def poly(p, color, points):
    p.setPen(Qt.PenStyle.NoPen); p.setBrush(QColor(color))
    p.drawPolygon(QPolygon([QPoint(x, y) for x, y in points]))

def headphones(p):
    dark = '#17151a'; charcoal = '#37363d'; shine = '#77757c'
    # A stepped headband arches around the ears without replacing them.
    for x,y,w,h in [(48,12,84,4),(43,16,94,4),(39,20,7,10),(134,20,7,10),
                    (36,29,6,34),(138,29,6,34)]: rect(p,dark,x,y,w,h)
    for x,y,w,h in [(49,13,82,2),(43,20,3,9),(134,20,3,9),(38,30,2,25),(140,30,2,25)]:
        rect(p,charcoal,x,y,w,h)
    for x in (40,130):
        rect(p,dark,x,58,11,24); rect(p,charcoal,x+2,60,7,20)
        rect(p,'#514f58',x+3,62,5,15); rect(p,shine,x+4,64,2,8)
        rect(p,dark,x+2,81,7,2)

def glasses(p):
    dark = '#100f12'; lens = '#25252a'; shine = '#737c7c'
    rect(p,dark,47,65,86,5)
    for x in (49,100):
        poly(p,dark,[(x,68),(x+31,68),(x+29,79),(x+25,83),(x+5,83),(x+2,79)])
        poly(p,lens,[(x+3,70),(x+28,70),(x+26,78),(x+23,80),(x+7,80),(x+4,77)])
        rect(p,shine,x+6,71,7,2); rect(p,shine,x+5,73,3,1)
    rect(p,dark,79,70,22,4)

def chain(p):
    dark = '#77501b'; gold = '#dcaa35'; light = '#ffe082'
    # Individual squared links form a thick chain across the jacket.
    points = [(60,121),(63,125),(66,129),(69,133),(72,137),(75,141),(79,145),
              (83,148),(87,151),(91,151),(95,148),(99,145),(103,141),(106,137),
              (109,133),(112,129),(115,125),(118,121)]
    for x,y in points:
        rect(p,dark,x-2,y-1,6,6); rect(p,gold,x-1,y,4,4); rect(p,light,x,y,2,2)
    rect(p,dark,86,155,9,9); rect(p,gold,87,156,7,7); rect(p,light,89,157,3,2)

create('headphones', headphones)
create('glasses', glasses)
create('gold-chain', chain)

def side_headphones(p):
    for x,y,w,h,c in [(85,19,5,8,'#17151a'),(89,15,5,5,'#17151a'),
                      (93,12,25,5,'#17151a'),(116,16,6,5,'#17151a'),
                      (118,20,5,10,'#17151a'),(115,28,6,31,'#17151a'),
                      (105,56,19,32,'#17151a'),(107,59,15,26,'#37363d'),
                      (110,62,9,20,'#514f58'),(112,64,3,11,'#77757c'),
                      (94,13,21,2,'#77757c')]:
        rect(p,c,x,y,w,h)

def side_glasses(p):
    rect(p,'#100f12',57,66,49,4)
    poly(p,'#100f12',[(58,69),(84,69),(82,80),(78,83),(63,83),(59,79)])
    poly(p,'#25252a',[(61,71),(81,71),(79,78),(76,80),(64,80),(61,77)])
    rect(p,'#737c7c',64,72,6,2)

def side_chain(p):
    for x,y in [(67,121),(69,125),(71,129),(73,133),(75,137),(78,141),(81,144),
                (84,145),(88,143),(92,140),(96,136),(99,132),(102,128),(105,124)]:
        rect(p,'#77501b',x-2,y-1,5,5); rect(p,'#dcaa35',x-1,y,3,3); rect(p,'#ffe082',x,y,2,1)
    rect(p,'#77501b',81,148,7,7); rect(p,'#dcaa35',82,149,5,5)

def turn_headphones(p):
    for x,y,w,h,c in [(53,12,72,4,'#17151a'),(47,16,6,5,'#17151a'),
                      (43,21,5,34,'#17151a'),(124,16,6,5,'#17151a'),
                      (129,21,5,34,'#17151a'),(44,58,11,23,'#17151a'),
                      (125,58,11,23,'#17151a'),(46,60,7,19,'#37363d'),
                      (127,60,7,19,'#37363d'),(47,62,5,14,'#514f58'),
                      (128,62,5,14,'#514f58'),(48,64,2,8,'#77757c'),
                      (129,64,2,8,'#77757c'),(54,13,69,2,'#77757c')]:
        rect(p,c,x,y,w,h)

def turn_glasses(p):
    rect(p,'#100f12',44,65,63,4)
    for x, w in ((45,20),(77,29)):
        poly(p,'#100f12',[(x,68),(x+w,68),(x+w-2,79),(x+w-5,82),(x+4,82),(x+1,78)])
        poly(p,'#25252a',[(x+2,70),(x+w-3,70),(x+w-4,77),(x+w-7,79),(x+5,79),(x+3,76)])
        rect(p,'#737c7c',x+5,71,5,2)
    rect(p,'#100f12',64,70,14,3)

for name, front, side, turn in (('headphones', headphones, side_headphones, turn_headphones),
                                ('glasses', glasses, side_glasses, turn_glasses),
                                ('gold-chain', chain, side_chain, None)):
    image = QImage(720, 220, QImage.Format.Format_RGBA8888); image.fill(Qt.GlobalColor.transparent)
    painter = QPainter(image)
    for frame in range(4):
        painter.save(); painter.translate(frame * 180, 0)
        if frame < 3:
            side(painter)
        elif turn:
            turn(painter)
        else:
            painter.translate(8, 0); painter.scale(0.8, 1)
            front(painter)
        painter.restore()
    painter.end()
    assert image.save(str(out / f'entry-{name}.png'))
