"""Pixel clothing overlays for Yecatz. Requires PySide6."""
from pathlib import Path
from PySide6.QtCore import QPoint, Qt
from PySide6.QtGui import QColor, QImage, QPainter, QPolygon, QRegion
root=Path(__file__).resolve().parent.parent
out=root/'Assets'/'Wardrobe'

def rect(p,c,x,y,w,h):p.fillRect(x,y,w,h,QColor(c))
def poly(p,c,pts):
 p.setPen(Qt.PenStyle.NoPen);p.setBrush(QColor(c));p.drawPolygon(QPolygon([QPoint(x,y) for x,y in pts]))

def paint(p,kind,center,side=False):
 if kind=='jewel':
  x=center
  left,right=(-35,56) if side else ((-43,58) if center==80 else (-50,50))
  if side:
   outline=[(x+6,22),(x+15,23),(x+29,14),(x+40,14),(x+51,20),(x+54,46),(x+56,67),(x+56,88),(x+49,101),(x+31,111),(x+17,116),(x-12,116),(x-27,109),(x-35,98),(x-35,88),(x-27,76),(x-21,64),(x-10,52),(x+3,45)]
   inner=[(x+9,25),(x+15,26),(x+30,17),(x+39,17),(x+48,23),(x+51,47),(x+53,68),(x+53,87),(x+46,99),(x+29,108),(x+16,113),(x-11,113),(x-24,106),(x-32,97),(x-32,89),(x-24,77),(x-18,66),(x-8,54),(x+6,47)]
  elif center==80:
   outline=[(x-25,19),(x-17,19),(x+4,44),(x+19,44),(x+46,17),(x+56,17),(x+59,52),(x+57,91),(x+52,103),(x+40,111),(x+26,116),(x-20,116),(x-31,111),(x-39,102),(x-42,90),(x-39,68),(x-34,54),(x-27,47)]
   inner=[(x-22,22),(x-18,22),(x+3,47),(x+20,47),(x+47,20),(x+53,20),(x+56,53),(x+54,90),(x+49,101),(x+38,108),(x+25,113),(x-19,113),(x-29,108),(x-36,100),(x-39,89),(x-36,69),(x-31,56),(x-24,49)]
  else:
   outline=[(x+left+2,19),(x+left+10,19),(x-20,44),(x+20,44),(x+right-10,19),(x+right-2,19),(x+right,52),(x+right,91),(x+right-5,103),(x+right-14,111),(x+right-25,116),(x+left+25,116),(x+left+14,111),(x+left+5,103),(x+left,91),(x+left,52)]
   inner=[(x+left+5,22),(x+left+9,22),(x-21,47),(x+21,47),(x+right-9,22),(x+right-5,22),(x+right-3,53),(x+right-3,90),(x+right-8,101),(x+right-16,108),(x+right-26,113),(x+left+26,113),(x+left+16,108),(x+left+8,101),(x+left+3,90),(x+left+3,53)]
  poly(p,'#17151d',outline);poly(p,'#393741',inner)
  p.save();p.setClipRegion(QRegion(QPolygon([QPoint(a,b) for a,b in inner])))
  for row,y in enumerate(range(21,113,6)):
   for col,dx in enumerate(range(left+8,right-5,7)):
    xx=x+dx+(3 if row%2 else 0)
    color=('#a8a5ad','#d9d4d9','#777580')[(row*3+col*2)%3]
    rect(p,color,xx,y,3,3)
    if (row+col)%4==0:rect(p,'#f3eee7',xx+1,y,1,1)
  p.restore()
 elif kind=='walker':
  x=center; ink='#17171b'; black='#25262c'; shade='#41434a'
  left,right = (-34,53) if side else (-45,45)
  poly(p,ink,[(x+left,91),(x+left+5,87),(x+right-5,87),(x+right,91),(x+right-5,107),(x+25,113),(x-25,113),(x+left+5,107)])
  poly(p,black,[(x+left+3,92),(x+left+7,89),(x+right-7,89),(x+right-3,92),(x+right-7,104),(x+23,110),(x-23,110),(x+left+7,104)])
  rect(p,shade,x+left+7,91,right-left-14,2)
  # White, angular interlocking AW monogram in the spirit of Alan Walker's mark.
  white='#e8e9e5'
  for xx,yy in [(-13,104),(-11,101),(-9,98),(-7,95),(-5,98),(-3,101),(-1,104),
                (0,95),(1,98),(2,101),(3,104),(5,101),(7,98),(8,101),(9,104),(11,101),(12,98),(13,95)]:
   rect(p,white,x+xx,yy,2,2)
  rect(p,white,x-10,102,8,2)
 elif kind in ('formal','tails'):
  # Satin lapel edge and buttons follow the original jacket silhouette.
  light='#77737b'; shadow='#19171d'
  if side:
   for i in range(10):rect(p,light,center+12+i*2,119+i*2,3,3)
   rect(p,'#d5c4a5',center+5,160,2,2)
   if kind=='tails':
    poly(p,shadow,[(center+17,173),(center+35,171),(center+39,198),(center+28,202),(center+21,186)])
    poly(p,'#35313a',[(center+20,175),(center+33,174),(center+36,195),(center+29,198),(center+23,184)])
  else:
   for i in range(10):
    rect(p,light,center-25+i*2,120+i*2,3,3);rect(p,light,center+22-i*2,120+i*2,3,3)
   for y in (158,168):rect(p,'#b9a785',center+1,y,2,2)
   if kind=='tails':
    for direction in (-1,1):
     poly(p,shadow,[(center+direction*15,174),(center+direction*31,174),(center+direction*35,200),(center+direction*23,203),(center+direction*17,187)])
     poly(p,'#35313a',[(center+direction*18,176),(center+direction*29,176),(center+direction*32,197),(center+direction*25,199),(center+direction*20,186)])

for name in ('cat','cat-blink','cat-entry'):
 original=QImage(str(root/'Assets'/f'{name}.png'))
 entry=name=='cat-entry';width=720 if entry else 180
 small=original.scaled(width,220,Qt.AspectRatioMode.IgnoreAspectRatio,Qt.TransformationMode.FastTransformation)
 for kind in ('formal','tails','walker','jewel','glove-white','glove-black'):
  layer=QImage(width,220,QImage.Format.Format_RGBA8888);layer.fill(Qt.GlobalColor.transparent)
  if kind=='jewel':
   for i in range(4 if entry else 1):
    offset=i*180 if entry else 0
    for y in range(16,114):
     for xx in range(180):
      c=small.pixelColor(offset+xx,y)
      if c.alpha()<80:continue
      neighbours=[small.pixelColor(offset+max(0,min(179,xx+dx)),max(0,min(219,y+dy))).alpha() for dx,dy in ((-1,0),(1,0),(0,-1),(0,1))]
      if sum(a>=80 for a in neighbours)<2:continue
      alpha=c.alpha()
      edge=any(a<80 for a in neighbours)
      color=QColor('#19171d' if edge else '#393741')
      if not edge and y%6 in (0,1,2) and (xx+(3 if (y//6)%2 else 0))%7 in (0,1,2):
       color=QColor(('#a8a5ad','#d9d4d9','#777580')[(y//6+xx//7)%3])
      color.setAlpha(alpha);layer.setPixelColor(offset+xx,y,color)
   # A few different stones catch the light on each frame, without changing the mask.
   for phase in range(4):
    sparkle=QImage(width,220,QImage.Format.Format_RGBA8888);sparkle.fill(Qt.GlobalColor.transparent)
    for cell in range(4 if entry else 1):
     offset=cell*180 if entry else 0
     for row,y in enumerate(range(24,110,12)):
      for col,xx in enumerate(range(30,151,14)):
       if (row*7+col*3)%4 != phase:continue
       if layer.pixelColor(offset+xx,y).alpha()<220:continue
       for dx,dy,color in [(0,0,'#fffdf2'),(-1,0,'#e9e7e8'),(1,0,'#e9e7e8'),(0,-1,'#e9e7e8'),(0,1,'#e9e7e8')]:
        px,py=offset+xx+dx,y+dy
        if layer.pixelColor(px,py).alpha()>=220:sparkle.setPixelColor(px,py,QColor(color))
    sparkle=sparkle.scaled(original.width(),original.height(),Qt.AspectRatioMode.IgnoreAspectRatio,Qt.TransformationMode.FastTransformation)
    assert sparkle.save(str(out/f'{name}-clothes-jewel-spark-{phase}.png'))
  elif kind.startswith('glove-'):
   # Recolor only orange pixels in the hand-height region; retain the original paw silhouette.
   for y in range(135,178):
    for x in range(width):
     c=small.pixelColor(x,y)
     if c.alpha()>80 and c.red()>110 and c.red()>c.green()*1.2 and c.green()>40 and c.green()>c.blue()*1.1:
      lum=(c.red()+c.green()+c.blue())/3
      if kind=='glove-white': v=max(145,min(245,int(175+(lum-100)*0.48)))
      else:v=max(30,min(90,int(45+(lum-100)*0.22)))
      layer.setPixelColor(x,y,QColor(v,v-2,v-1,c.alpha()))
  else:
   p=QPainter(layer)
   if entry:
    for i in range(4):
     p.save();p.translate(i*180,0);paint(p,kind,74 if i<3 else 80,i<3);p.restore()
   else:paint(p,kind,90)
   p.end()
  # Smooth only the mask layer's scaled edges; the original sprite remains pixel-sharp.
  mode = Qt.TransformationMode.SmoothTransformation if kind=='jewel' else Qt.TransformationMode.FastTransformation
  layer=layer.scaled(original.width(),original.height(),Qt.AspectRatioMode.IgnoreAspectRatio,mode)
  assert layer.save(str(out/f'{name}-clothes-{kind}.png'))
 eraser=QImage(original.width(),original.height(),QImage.Format.Format_RGBA8888);eraser.fill(Qt.GlobalColor.transparent)
 p=QPainter(eraser);p.fillRect(0,0,original.width(),round(original.height()*114/220),QColor('white'));p.end()
 assert eraser.save(str(out/f'{name}-clothes-jewel-erase.png'))
 print(name,'done')
