#!/usr/bin/env python3
"""Reproduce Orbit's geometric artwork using the established app-suite pipeline."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SIZE = 1536
SCALE = SIZE / 256
y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / (SIZE - 1)


def rgb(value):
    return np.array(tuple(bytes.fromhex(value.removeprefix('#'))), dtype=np.float32)


tl, tr, bl, br = map(rgb, ['#A2E6F5', '#8C9AEA', '#437FC0', '#6652A5'])
top = tl * (1 - x[..., None]) + tr * x[..., None]
bottom = bl * (1 - x[..., None]) + br * x[..., None]
background = top * (1 - y[..., None]) + bottom * y[..., None]
canvas = Image.fromarray(np.clip(background, 0, 255).astype('uint8')).convert('RGBA')


def polygon(draw, points, fill):
    draw.polygon([(round(px * SCALE), round(py * SCALE)) for px, py in points], fill=fill)


shadow = Image.new('RGBA', (SIZE, SIZE))
sd = ImageDraw.Draw(shadow)
polygon(sd, [(59, 66), (165, 49), (202, 179), (91, 213)], '#172C666E')
shadow = shadow.filter(ImageFilter.GaussianBlur(9 * SCALE))
canvas = Image.alpha_composite(canvas, shadow)
draw = ImageDraw.Draw(canvas)

# Successive offset glass planes make the spatial-video identity visible at small sizes.
polygon(draw, [(49, 61), (153, 39), (181, 163), (77, 185)], '#BBD5F1')
polygon(draw, [(49, 61), (153, 39), (154, 42), (51, 64)], '#EDFAFF')
polygon(draw, [(154, 42), (181, 163), (178, 166), (151, 44)], '#8AA8DB')
polygon(draw, [(55, 73), (161, 48), (190, 174), (84, 199)], '#98C4E8')
polygon(draw, [(55, 73), (161, 48), (162, 51), (57, 76)], '#DBF3FF')
polygon(draw, [(62, 85), (170, 58), (200, 186), (92, 213)], '#E7F7FF')
polygon(draw, [(62, 85), (116, 72), (146, 199), (92, 213)], '#F5FCFF')
polygon(draw, [(116, 72), (170, 58), (200, 186), (146, 199)], '#CBE5F6')
polygon(draw, [(170, 58), (173, 58), (203, 186), (200, 190), (200, 186)], '#97BAE5')
polygon(draw, [(92, 213), (200, 186), (200, 190), (92, 217)], '#B6D7EE')
polygon(draw, [(62, 85), (170, 58), (170, 61), (64, 88)], '#FFFFFF')

# A beveled play symbol is recessed into the foreground pane.
polygon(draw, [(113, 105), (160, 126), (127, 166)], '#8E8BD0')
polygon(draw, [(113, 105), (160, 126), (157, 130), (116, 112)], '#B2AAE8')
polygon(draw, [(116, 112), (157, 130), (128, 164)], '#7694D3')
polygon(draw, [(113, 105), (116, 112), (128, 164), (127, 166)], '#5F7DBE')

native = canvas.convert('RGB').resize((1024, 1024), Image.Resampling.LANCZOS)
native_path = ROOT / 'Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
native_path.parent.mkdir(parents=True, exist_ok=True)
native.save(native_path, optimize=True)
catalog = native.convert('RGBA')
mask = Image.new('L', catalog.size)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1023, 1023), radius=218, fill=255)
catalog.putalpha(mask)
catalog.save(ROOT.parent / 'assets/Orbit.png', optimize=True)
print('Created the opaque native master and matching rounded catalog icon.')
