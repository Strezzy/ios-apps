#!/usr/bin/env python3
"""Draw Collectr's original code-native icon, using only the Python stdlib."""
import math, struct, zlib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
W = 1024

def mix(a,b,t): return tuple(a[i]*(1-t)+b[i]*t for i in range(3))
def rounded(x,y,cx,cy,w,h,r,angle):
    dx=x-cx;dy=y-cy;c=math.cos(angle);s=math.sin(angle)
    px=dx*c+dy*s;py=-dx*s+dy*c
    qx=abs(px)-(w/2-r);qy=abs(py)-(h/2-r)
    return math.hypot(max(0,qx),max(0,qy))+min(max(qx,qy),0)-r,px,py
rows=[]
for y in range(W):
    row=bytearray([0])
    for x in range(W):
        glow=max(0,1-math.hypot(x-420,y-370)/760)
        col=mix((10,15,25),(37,54,77),glow)
        d,px,py=rounded(x,y,530,535,493,686,39,-.13)
        if d<4:
            t=min(1,max(0,(4-d)/3))
            edge=max(0,1-abs(d)/5)
            col=mix(col,(105+edge*110,134+edge*100,165+edge*85),(.1+edge*.5)*t)
        d,px,py=rounded(x,y,502,503,461,648,28,.075)
        if d<0:
            v=(py+324)/648;u=(px+230)/461
            photo=mix((106,163,184),(208,116,121),min(1,max(0,v)))
            # A luminous pearl above a tranquil ridgeline.
            sphere=math.hypot(px+7,py+85)
            if sphere<108:
                light=max(0,1-math.hypot(px+42,py+130)/195)
                photo=mix((67,91,127),(236,231,221),light)
            ridge=100+35*math.sin(px/97)+12*math.sin(px/31)
            if py>ridge: photo=mix((36,61,91),(17,28,48),(py-ridge)/280)
            if py>241: photo=mix(photo,(12,20,34),.7)
            if py>267 and py<273 and -170<px< -55: photo=(210,216,225)
            if py>267 and py<273 and 97<px<170: photo=(210,216,225)
            edge=max(0,1-abs(d)/3)
            glint=math.exp(-((u+v*.7-.4)/.12)**2)*.12
            photo=mix(photo,(239,248,255),min(.8,edge*.8+glint))
            col=photo
        row.extend(max(0,min(255,round(c))) for c in (*col,255))
    rows.append(bytes(row))
def chunk(name,data): return struct.pack('>I',len(data))+name+data+struct.pack('>I',zlib.crc32(name+data)&0xffffffff)
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',W,W,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b'')
path=ROOT/'Assets.xcassets/AppIcon.appiconset/AppIcon.png';path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(png)
print(f'Created {path.name}: {len(png):,} bytes')
