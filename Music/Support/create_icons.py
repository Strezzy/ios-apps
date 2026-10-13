#!/usr/bin/env python3
"""Render Music's five original geometric alternate icons with Pillow.

All artwork is constructed from vector-like primitives at 2x resolution.
Opaque square canvases let iOS apply its own Home Screen corner mask.
No third-party artwork, font glyphs, or downloaded graphics are used.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import math

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Resources"
SIZE = 2048
SCALE = SIZE / 1024

def rect(box):
    return tuple(round(x * SCALE) for x in box)

def gradient(stops, diagonal=False):
    ramp = Image.new("RGB", (1, SIZE))
    pixels = []
    for y in range(SIZE):
        t = y / (SIZE-1)
        for (a, ca), (b, cb) in zip(stops, stops[1:]):
            if a <= t <= b:
                q = (t-a)/(b-a)
                pixels.append(tuple(round(x+(z-x)*q) for x,z in zip(ca,cb)))
                break
    ramp.putdata(pixels)
    return ramp.resize((SIZE,SIZE))

def ellipse(draw, box, fill, width=None):
    if width is None: draw.ellipse(rect(box),fill=fill)
    else: draw.ellipse(rect(box),outline=fill,width=round(width*SCALE))

def line(draw, pts, fill, width):
    draw.line([(round(x*SCALE),round(y*SCALE)) for x,y in pts],fill=fill,width=round(width*SCALE))

def note_mask(broken=False):
    mask=Image.new("L",(SIZE,SIZE))
    d=ImageDraw.Draw(mask)
    d.rounded_rectangle(rect((395,292,445,671)),radius=9*SCALE,fill=255)
    d.rounded_rectangle(rect((621,242,671,622)),radius=9*SCALE,fill=255)
    d.polygon([tuple(round(v*SCALE) for v in p) for p in ((395,292),(671,232),(671,315),(395,375))],fill=255)
    # Angled, compact note heads keep the sign optically balanced.
    for cx,cy in ((352,677),(578,628)):
        head=Image.new("L",(240,180))
        ImageDraw.Draw(head).ellipse((15,28,225,152),fill=255)
        head=head.rotate(14,resample=Image.Resampling.BICUBIC,expand=True)
        head=head.resize((round(head.width*SCALE*.88),round(head.height*SCALE*.88)),Image.Resampling.LANCZOS)
        mask.paste(head,(round(cx*SCALE-head.width/2),round(cy*SCALE-head.height/2)),head)
    if broken:
        d.polygon([tuple(round(v*SCALE) for v in p) for p in ((569,242),(596,238),(565,341),(538,347))],fill=0)
    return mask

def shine(image, center, color, opacity, radius):
    mask=Image.new("L",(SIZE,SIZE))
    d=ImageDraw.Draw(mask)
    x,y=center
    ellipse(d,(x-radius,y-radius,x+radius,y+radius),round(opacity*255))
    mask=mask.filter(ImageFilter.GaussianBlur(radius*SCALE*.55))
    image.paste(Image.new("RGB",image.size,color),(0,0),mask)

def make_noir():
    image=gradient([(0,(35,38,43)),(.5,(15,17,21)),(1,(3,4,7))])
    mask=note_mask(True)
    image.paste(gradient([(0,(255,255,255)),(1,(201,209,219))]),(0,0),mask)
    return image

def make_ivory():
    image=gradient([(0,(255,253,246)),(1,(226,219,204))])
    d=ImageDraw.Draw(image)
    # An open, fine-lined record with an offset needle: quiet editorial style.
    for radius,width,color in ((237,9,(41,40,37)),(207,3,(164,153,135))):
        ellipse(d,(512-radius,512-radius,512+radius,512+radius),color,width)
    ellipse(d,(454,454,570,570),(39,38,35))
    ellipse(d,(500,500,524,524),(245,241,229))
    line(d,((699,278),(704,498),(596,608)),(39,38,35),20)
    d.rounded_rectangle(rect((572,587,614,636)),radius=8*SCALE,fill=(39,38,35))
    return image

def make_aurora():
    image=gradient([(0,(32,56,91)),(.55,(58,38,96)),(1,(18,26,49))])
    shine(image,(248,266),(56,205,183),.95,325)
    shine(image,(788,734),(164,94,227),.84,365)
    mask=note_mask(False)
    # A restrained frosted sign with a narrow luminous rim.
    expanded=mask.filter(ImageFilter.MaxFilter(9))
    image.paste((197,240,250),(0,0),expanded.point(lambda p:round(p*.68)))
    image.paste(gradient([(0,(247,255,255)),(.55,(181,218,238)),(1,(219,205,245))]),(0,0),mask)
    return image

def make_signal():
    image=gradient([(0,(251,76,88)),(1,(204,37,64))])
    d=ImageDraw.Draw(image)
    widths=52
    for center,height in zip((314,413,512,611,710),(132,292,432,292,132)):
        d.rounded_rectangle(rect((center-widths/2,512-height/2,center+widths/2,512+height/2)),radius=widths*SCALE/2,fill=(255,250,246))
    return image

def make_chrome():
    image=gradient([(0,(226,232,238)),(.25,(162,171,183)),(.54,(230,234,239)),(.78,(175,183,195)),(1,(219,225,233))])
    d=ImageDraw.Draw(image)
    # Metallic disc, defined by crisp concentric machining and a tiny red hub.
    ellipse(d,(231,231,793,793),(72,82,98))
    disc=gradient([(0,(253,254,255)),(.28,(216,224,231)),(.49,(99,111,128)),(.51,(201,212,223)),(.72,(234,239,244)),(1,(129,143,160))])
    mask=Image.new("L",image.size); ellipse(ImageDraw.Draw(mask),(241,241,783,783),255)
    image.paste(disc,(0,0),mask)
    d=ImageDraw.Draw(image)
    for radius,opacity in ((240,105),(216,85),(191,75),(166,65)):
        ellipse(d,(512-radius,512-radius,512+radius,512+radius),(139,153,170),2)
    ellipse(d,(431,431,593,593),(54,64,81))
    ellipse(d,(444,444,580,580),(218,63,83))
    ellipse(d,(498,498,526,526),(236,240,245))
    return image

def main():
    sizes={"20x20":(1,2,3),"29x29":(1,2,3),"40x40":(1,2,3),"60x60":(2,3),"76x76":(1,2),"83.5x83.5":(2,)}
    for name,maker in (("Noir",make_noir),("Ivory",make_ivory),("Aurora",make_aurora),("Signal",make_signal),("Chrome",make_chrome)):
        art=maker()
        art.resize((1024,1024),Image.Resampling.LANCZOS).save(OUT/f"Icon{name}Preview.png",optimize=True)
        for base,scales in sizes.items():
            for scale in scales:
                side=round(float(base.split('x')[0])*scale)
                suffix=f"@{scale}x" if scale!=1 else ""
                art.resize((side,side),Image.Resampling.LANCZOS).save(OUT/f"Icon{name}{base}{suffix}.png",optimize=True)
        print(name)

if __name__=="__main__": main()
