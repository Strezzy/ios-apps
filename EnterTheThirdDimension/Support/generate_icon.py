#!/usr/bin/env python3
"""Render the original app icon from the same code-native courier pixels.

Development utility: Python + Pillow + Node. The generated RGB PNG is checked
in; these tools are not required by the iPhone app or the Mac build workflow.
"""
from pathlib import Path
import json
import math
import subprocess
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
script = "global.window={};require(process.argv[1]);process.stdout.write(JSON.stringify(window.TD_ART.sprites.hero[0]));"
sprite = json.loads(subprocess.check_output(["node", "-e", script, str(ROOT / "Resources/Game/art.js")]))
size = 1024
image = Image.new("RGB", (size, size))
px = image.load()
for y in range(size):
    for x in range(size):
        glow = math.exp(-(((x - 610) / 530) ** 2 + ((y - 440) / 610) ** 2) * 2)
        aurora = math.exp(-((y - 270 - 48 * math.sin(x / 195)) / 62) ** 2)
        px[x, y] = (int(13 + 19 * glow + 5 * aurora), int(24 + 36 * glow + 24 * aurora), int(45 + 32 * glow + 18 * aurora))
draw = ImageDraw.Draw(image)
for i in range(50):
    x = int((math.sin(i * 127.1) * 4375.12 % 1) * 1024)
    y = int((math.sin(i * 39.7 + 7) * 9173.12 % 1) * 820)
    if i % 7 == 0:
        draw.rectangle((x - 2, y - 8, x + 2, y + 8), fill="#809eaa")
        draw.rectangle((x - 8, y - 2, x + 8, y + 2), fill="#809eaa")
    else:
        draw.rectangle((x, y, x + 3, y + 3), fill="#546f82")

# A square opens into a volume behind the courier.
line = Image.new("RGBA", image.size)
ld = ImageDraw.Draw(line)
flat = [(228, 323), (506, 323), (506, 675), (228, 675), (228, 323)]
ld.line(flat, fill=(151, 138, 195, 120), width=7)
for y in range(350, 660, 31):
    ld.line([(242, y), (275, y)], fill=(151, 138, 195, 70), width=4)
front = [(430, 259), (755, 335), (755, 690), (430, 615), (430, 259)]
back = [(565, 183), (890, 259), (890, 614), (755, 690)]
ld.line(front, fill=(139, 248, 218, 190), width=7)
ld.line(back, fill=(139, 248, 218, 160), width=7)
ld.line([(430, 259), (565, 183)], fill=(189, 255, 229, 210), width=7)
ld.line([(755, 335), (890, 259)], fill=(189, 255, 229, 210), width=7)
ld.line([(430, 615), (565, 539), (890, 614)], fill=(139, 248, 218, 65), width=4)
image = Image.alpha_composite(image.convert("RGBA"), line.filter(ImageFilter.GaussianBlur(18)))
image = Image.alpha_composite(image, line).convert("RGB")
draw = ImageDraw.Draw(image)

# A floating pixel cliff and its solid top face.
draw.polygon([(179, 719), (508, 622), (846, 722), (518, 841)], fill="#79b7a5")
draw.polygon([(179, 719), (518, 819), (518, 903), (238, 821), (238, 782), (179, 764)], fill="#294857")
draw.polygon([(518, 819), (846, 722), (846, 775), (791, 792), (791, 834), (518, 916)], fill="#1b354a")
draw.line([(179, 719), (518, 819), (846, 722)], fill="#bbe4bd", width=8)
for x, y, w in [(263, 773, 43), (335, 806, 38), (447, 846, 32), (594, 851, 29), (693, 820, 46), (752, 778, 24)]:
    draw.rectangle((x, y, x+w, y+12), fill="#3c6070")
draw.polygon([(351, 716), (507, 670), (666, 716), (510, 765)], fill="#48746d")

def rgb(hex_color):
    return tuple(int(hex_color[i:i+2], 16) for i in (1, 3, 5))

def shade(c, f):
    return tuple(max(0, min(255, round(v*f))) for v in c)

# Match the game's actual pixel extrusion. Draw side surfaces, then the face.
unit = 13
def point(x, y, depth=0):
    return (round(491 + (x-12)*unit*.94 + depth*.78), round(733 - (30-y)*unit + (x-12)*unit*.19 - depth*.36))

for row, pixels in enumerate(sprite["rows"]):
    for col, key in enumerate(pixels):
        if key not in sprite["palette"]:
            continue
        color = rgb(sprite["palette"][key])
        p0, p1, p2, p3 = point(col, row), point(col+1, row), point(col+1, row+1), point(col, row+1)
        q0, q1, q2, q3 = point(col, row, 95), point(col+1, row, 95), point(col+1, row+1, 95), point(col, row+1, 95)
        draw.polygon([p0, q0, q1, p1], fill=shade(color, .95))
        draw.polygon([p1, q1, q2, p2], fill=shade(color, .65))
        draw.polygon([q0, q1, q2, q3], fill=shade(color, .78))
for row, pixels in enumerate(sprite["rows"]):
    for col, key in enumerate(pixels):
        if key in sprite["palette"]:
            draw.polygon([point(col,row),point(col+1,row),point(col+1,row+1),point(col,row+1)],fill=rgb(sprite["palette"][key]))

def prism(x, y, r):
    draw.polygon([(x,y-r),(x+r*.62,y),(x,y+r),(x-r*.62,y)], fill="#cdb3ff")
    draw.polygon([(x,y-r),(x,y),(x-r*.62,y)], fill="#f0e0ff")
    draw.polygon([(x,y),(x+r*.62,y),(x,y+r)], fill="#927ac3")
    draw.line([(x,y-r),(x,y+r)], fill="#eadbff", width=3)
prism(760, 218, 49)
for x,y in [(297,265),(806,500),(290,622),(654,332)]:
    draw.rectangle((x-3,y-13,x+3,y+13),fill="#e4d3a3")
    draw.rectangle((x-13,y-3,x+13,y+3),fill="#e4d3a3")

target = ROOT / "Resources/AppIcon1024.png"
image.convert("RGB").save(target, optimize=True)
image.resize((512,512),Image.Resampling.LANCZOS).convert("RGB").save(ROOT.parent / "assets/ThirdDimension.png", optimize=True)
print(target)
