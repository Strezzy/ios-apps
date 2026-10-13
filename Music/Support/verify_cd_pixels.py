#!/usr/bin/env python3
"""Check actual saved WebGL pixels after verify_cd_renderer.mjs.

Previews stay in development scratch, outside the source/app archives.
"""
import json
import os
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
previews = Path(os.environ.get('MUSIC_CD_PREVIEW_DIR', str(root.parent / 'cd-render-previews')))
closed = Image.open(previews / 'hero-closed.png').convert('RGBA')
w, h = closed.size
corners = [(0,0),(w-1,0),(0,h-1),(w-1,h-1)]
alpha = [closed.getpixel(p)[3] for p in corners]
# The cast soft shadow can reach a lower corner; it is intentionally alpha,
# not an opaque page. Require fully clear space and only light shadow elsewhere.
assert sum(a == 0 for a in alpha) >= 3 and max(alpha) < 64, alpha
red = Image.open(previews / 'artwork-red.png').convert('RGBA').getpixel((240,120))
blue = Image.open(previews / 'artwork-blue.png').convert('RGBA').getpixel((240,120))
assert red[0] > red[2]+60 and blue[2] > blue[0]+60 and red[3] == blue[3] == 255, (red,blue)
checks = [
    {'name':'Transparent canvas with translucent case shadow preserves native background', 'passed':True, 'corner_alpha':alpha},
    {'name':'Disc print pixels visibly change from red to blue artwork', 'passed':True, 'red_RGBA':red, 'blue_RGBA':blue},
]
p = root / 'Support/CD-RENDER-REPORT.json'
report = json.loads(p.read_text())
assert report['passed'] is True
names = {check['name'] for check in checks}
report['checks'] = [check for check in report['checks'] if check['name'] not in names] + checks
p.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({'passed':True,'checks':len(report['checks']),'corner_alpha':alpha,'red_RGBA':red,'blue_RGBA':blue}))
