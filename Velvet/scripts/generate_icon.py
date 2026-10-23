#!/usr/bin/env python3
"""Velvet's reproducible suite icon: sculpted ivory aperture on a burgundy field.
Shares the faceted geometry, directional highlights, and gradient language of
Facet, Veil, Lucid and Echo, without altering their assets.
"""
import math, json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
ROOT=Path(__file__).resolve().parents[1]
S=1536
corners=((200,115,145),(137,42,79),(117,38,68),(51,17,39))
img=Image.new('RGB',(S,S)); pix=img.load()
for y in range(S):
    v=y/(S-1)
    for x in range(S):
        u=x/(S-1)
        pix[x,y]=tuple(round(corners[0][i]*(1-u)*(1-v)+corners[1][i]*u*(1-v)+corners[2][i]*(1-u)*v+corners[3][i]*u*v) for i in range(3))
# Six broad folded aperture blades: central opening creates a quiet camera cue.
def ring(r,a):
    t=math.radians(a); return (128+r*math.cos(t),128+r*math.sin(t))
outer=[ring(82,-90+i*60) for i in range(6)]
inner=[ring(32,-60+i*60) for i in range(6)]
polys=[]
colors=['#FFF1EC','#F5D7DD','#D9ABB9','#C58B9F','#E4B3C1','#FCE2E6']
for i in range(6):
    j=(i+1)%6
    polys.append(([outer[i],outer[j],inner[j],inner[i]],colors[i]))
scale=S/256
shadow=Image.new('L',(S,S)); d=ImageDraw.Draw(shadow)
for p,c in polys:d.polygon([((x+1.5)*scale,(y+7)*scale) for x,y in p],fill=85)
shadow=shadow.filter(ImageFilter.GaussianBlur(6*scale)); shade=Image.new('RGB',(S,S),'#1b0c20'); img.paste(shade,(0,0),shadow)
d=ImageDraw.Draw(img)
for p,c in polys:d.polygon([(x*scale,y*scale) for x,y in p],fill=c)
for i in range(6):
    a,b=outer[i],outer[(i+1)%6]; d.line([(a[0]*scale,a[1]*scale),(b[0]*scale,b[1]*scale)], fill=('#FFF6EF' if i in (0,4,5) else '#DBADBA'),width=round(scale*0.8))
img=img.resize((1024,1024),Image.Resampling.LANCZOS)
for name in ['AppIcon.appiconset','Brand.imageset']:
    out=ROOT/'Velvet/Resources/Assets.xcassets'/name;out.mkdir(parents=True,exist_ok=True)
    img.save(out/'Velvet.png',optimize=True)
    entry={'idiom':'universal','filename':'Velvet.png'}
    if name.endswith('appiconset'):entry.update(platform='ios',size='1024x1024')
    (out/'Contents.json').write_text(json.dumps({'images':[entry],'info':{'version':1,'author':'xcode'}},indent=2)+'\n')
print('Generated 1024px opaque Velvet suite icon')
