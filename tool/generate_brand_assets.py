"""Reproducible, original Home Serve vector mark and platform icon exports.
Requires Pillow. No downloaded logo or third-party artwork is used.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/brand'
OUT.mkdir(parents=True, exist_ok=True)
SVG = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
<defs><linearGradient id="orange" x2="0.9" y2="1"><stop stop-color="#FF9548"/><stop offset="1" stop-color="#ED5200"/></linearGradient></defs>
<rect width="1024" height="1024" rx="230" fill="url(#orange)"/>
<g fill="none" stroke="white" stroke-width="60" stroke-linecap="round" stroke-linejoin="round">
<path d="M245 480 L512 255 L779 480 M305 435 V715 Q305 760 350 760 H674 Q719 760 719 715 V435"/>
<path d="M409 573 L484 648 L619 503"/></g></svg>'''
(OUT / 'home-serve.svg').write_text(SVG, encoding='utf-8')

def mark(size=1024, tile=True, rounded=False):
    scale = 2
    s = size * scale
    im = Image.new('RGBA', (s, s))
    if tile:
        d = ImageDraw.Draw(im)
        for y in range(s):
            t = y / (s-1)
            rgb = tuple(round(a+(b-a)*t) for a,b in zip((255,149,72),(237,82,0)))
            d.line((0,y,s,y), fill=rgb+(255,))
        if rounded:
            mask = Image.new('L', (s,s)); ImageDraw.Draw(mask).rounded_rectangle((0,0,s,s), radius=s*.225, fill=255)
            im.putalpha(mask)
    d = ImageDraw.Draw(im)
    def line(points, width=60):
        pts = [(round(x*s/1024),round(y*s/1024)) for x,y in points]
        w = round(width*s/1024)
        d.line(pts, fill='white', width=w, joint='curve')
        for x,y in pts:
            d.ellipse((x-w/2,y-w/2,x+w/2,y+w/2),fill='white')
    line([(245,480),(512,255),(779,480)])
    line([(305,435),(305,715),(307,735),(325,755),(350,760),(674,760),(699,755),(717,735),(719,715),(719,435)])
    line([(409,573),(484,648),(619,503)])
    return im.resize((size,size), Image.Resampling.LANCZOS)

mark(1024,rounded=True).save(OUT/'home-serve-mark.png')
mark(1024).convert('RGB').save(OUT/'home-serve-icon.png')
res = ROOT/'android/app/src/main/res'
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    mark(size,rounded=True).save(res/f'mipmap-{density}/ic_launcher.png')
for density,size in [('mdpi',120),('hdpi',180),('xhdpi',240),('xxhdpi',360),('xxxhdpi',480)]:
    folder=res/f'drawable-{density}'; folder.mkdir(exist_ok=True)
    mark(size,rounded=True).save(folder/'home_serve_launch.png')
icons=ROOT/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((icons/'Contents.json').read_text())['images']:
    size=round(float(item['size'].split('x')[0])*int(item['scale'][0]))
    mark(size).convert('RGB').save(icons/item['filename'])
launch=ROOT/'ios/Runner/Assets.xcassets/LaunchImage.imageset'
for scale in [1,2,3]:
    mark(120*scale,rounded=True).save(launch/('LaunchImage'+('' if scale==1 else f'@{scale}x')+'.png'))
for size in [192,512]:
    for prefix in ['Icon','Icon-maskable']:
        mark(size).convert('RGB').save(ROOT/f'web/icons/{prefix}-{size}.png')
mark(32,rounded=True).save(ROOT/'web/favicon.png')
print('Generated Home Serve platform icons and launch artwork.')
