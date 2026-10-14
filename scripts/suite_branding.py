#!/usr/bin/env python3
"""Render the approved app-suite artwork and synchronize public catalog metadata.

Only the four listed app identities are mutable. Bundle identifiers, downloads,
version histories, Music, and Prism are deliberately preserved.
"""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RAW = 'https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/'
BRANDS = {
    'com.billy.depthcheck': ('Facet', '#32AFE1', 'Depth Check'),
    'com.billy.rinse': ('Veil', '#20B894', 'Rinse'),
    'com.billy.lumalift': ('Lucid', '#CE8CBE', 'LumaLift'),
    'com.billy.voiceglass': ('Echo', '#A28AEF', 'VoiceGlass'),
}
PALETTES = {
    'Facet': ('#82DFEB', '#1AA4E5', '#246BA4', '#153C83'),
    'Veil': ('#98EFC3', '#11BB93', '#259470', '#006450'),
    'Lucid': ('#FFC0DE', '#C67BBD', '#A64E85', '#7D376F'),
    'Echo': ('#D1BFFC', '#9465E4', '#7960B3', '#492A83'),
}


def rgb(value):
    return np.array(tuple(bytes.fromhex(value.lstrip('#'))), dtype=np.float32)


def render(name: str, size: int = 1024) -> Image.Image:
    # Geometry is expressed in the approved preview's 256-pixel coordinate grid.
    scale = size / 256
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / (size - 1)
    tl, tr, bl, br = map(rgb, PALETTES[name])
    top = tl[None, None, :] * (1-x[..., None]) + tr[None, None, :] * x[..., None]
    bottom = bl[None, None, :] * (1-x[..., None]) + br[None, None, :] * x[..., None]
    background = top * (1-y[..., None]) + bottom * y[..., None]
    canvas = Image.fromarray(np.clip(background, 0, 255).astype('uint8')).convert('RGBA')
    shapes = []

    def poly(points, color):
        shapes.append((points, color))

    if name == 'Facet':
        # Three offset planes: identical perspective, sculpted edges and lighting.
        for cy in (172, 127, 82):
            top, left, right, lower = (128, cy-33), (57, cy), (199, cy), (128, cy+32)
            poly([left, lower, right, (199, cy+5), (128, cy+37), (57, cy+5)], '#76CFE5')
            poly([top, left, lower], '#DDF8F7')
            poly([top, lower, right], '#B5E8F0')
            poly([top, (128, cy+30), (167, cy-14)], '#C5EFF3')
            poly([left, (128, cy+32), (128, cy+35), (57, cy+3)], '#A7E4EE')
            poly([top, (57, cy), (59, cy+1), (128, cy-31), (197, cy+1), right], '#F0FFFF')
    elif name == 'Veil':
        poly([(58,77),(128,50),(197,77),(188,142),(128,204),(68,142)], '#B3EBCF')
        poly([(58,77),(128,50),(197,77),(128,120)], '#ECFFE9')
        poly([(58,77),(128,120),(128,204),(68,142)], '#D0F5DA')
        poly([(128,120),(197,77),(188,142),(128,204)], '#A8E2CA')
        poly([(181,87),(174,142),(128,204),(149,118)], '#BEECD5')
        poly([(58,77),(128,50),(197,77),(195,78),(128,52),(60,78)], '#F4FFF1')
        poly([(128,120),(129,120),(129,202),(128,204)], '#D6FFE4')
    elif name == 'Lucid':
        outer = [(98,54),(158,54),(202,98),(202,158),(158,202),(98,202),(54,158),(54,98)]
        inner = [(112,90),(144,90),(166,112),(166,144),(144,166),(112,166),(90,144),(90,112)]
        # A faint refractive diagonal within the open octagonal aperture.
        poly([(96,104),(112,90),(166,144),(151,159)], '#C387BA')
        colors = ['#FFF4E8','#F7DFEA','#F3D1E5','#E6B2D1','#D597BE','#EAB9D3','#F8D0E0','#FFE0E7']
        for i, color in enumerate(colors):
            j = (i+1) % 8
            poly([outer[i],outer[j],inner[j],inner[i]], color)
        poly([(98,54),(158,54),(157,56),(99,56)], '#FFF9EF')
    elif name == 'Echo':
        for cx, h in [(67,48),(98,90),(128,144),(159,90),(190,48)]:
            y0, y1, w, cut = 129-h/2, 129+h/2, 23, 5
            poly([(cx-w/2+cut,y0),(cx+w/2-cut,y0),(cx+w/2,y0+cut),(cx+w/2,y1-cut),(cx+w/2-cut,y1),(cx-w/2+cut,y1),(cx-w/2,y1-cut),(cx-w/2,y0+cut)], '#E7DEFA')
            poly([(cx-w/2+cut,y0),(cx+w/2-cut,y0),(cx+w/2,y0+cut),(cx-w/2,y0+cut)], '#FEFAFF')
            poly([(cx+w/2-cut,y0+cut),(cx+w/2,y0+cut),(cx+w/2,y1-cut),(cx+w/2-cut,y1)], '#BFAFE2')
            poly([(cx-w/2,y0+cut),(cx-w/2+3,y0+cut),(cx-w/2+3,y1-3),(cx-w/2,y1-cut)], '#F4EFFF')
    else:
        raise ValueError(f'Unknown approved brand: {name}')

    shadow = Image.new('L', (size,size))
    draw = ImageDraw.Draw(shadow)
    for points, _ in shapes:
        draw.polygon([(round((px+1.5)*scale),round((py+7)*scale)) for px,py in points], fill=80)
    shadow = shadow.filter(ImageFilter.GaussianBlur(6*scale))
    shade = Image.new('RGBA', (size,size), '#101325')
    shade.putalpha(shadow)
    canvas = Image.alpha_composite(canvas, shade)
    draw = ImageDraw.Draw(canvas)
    for points, color in shapes:
        draw.polygon([(round(px*scale),round(py*scale)) for px,py in points], fill=color)
    return canvas.convert('RGB')


def synchronize(root: Path) -> None:
    registry_path, catalog_path = root/'app-registry.json', root/'apps.json'
    registry = json.loads(registry_path.read_text())
    # Native renamed IDs supersede legacy catalog identities.
    for old_id, identity in list(BRANDS.items()):
        current_id = 'com.billy.' + identity[0].lower()
        if current_id in registry and old_id not in registry:
            BRANDS[current_id] = BRANDS.pop(old_id)
    catalog = json.loads(catalog_path.read_text())
    before_registry, before_catalog = copy.deepcopy(registry), copy.deepcopy(catalog)
    for bundle, (name, tint, _) in BRANDS.items():
        assert bundle in registry, f'Missing registered app {bundle}'
        registry[bundle].update(name=name, icon=f'{name}.png', tintColor=tint)
        matching = [a for a in catalog['apps'] if a['bundleIdentifier'] == bundle]
        assert len(matching) == 1, f'Expected one catalog entry for {bundle}'
        matching[0].update(name=name, iconURL=RAW+name+'.png', tintColor=tint)
        for key in ('downloadURL','versions','size','version','appPermissions'):
            if key in matching[0]:
                original = next(a for a in before_catalog['apps'] if a['bundleIdentifier'] == bundle)
                assert matching[0][key] == original[key], f'Unexpected release mutation: {bundle}/{key}'
        # Rinse's release job restores its app-local catalog entry; keep that in sync.
        if bundle == 'com.billy.rinse':
            local = root/'Rinse/catalog-entry.json'
            if local.exists():
                data = json.loads(local.read_text())
                data.update(name=name, icon=f'{name}.png', tintColor=tint)
                local.write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n')
    for bundle in set(registry) - set(BRANDS):
        assert registry[bundle] == before_registry[bundle], f'Unrelated registry change: {bundle}'
        assert next(a for a in catalog['apps'] if a['bundleIdentifier']==bundle) == next(a for a in before_catalog['apps'] if a['bundleIdentifier']==bundle)
    for path, data in [(registry_path, registry), (catalog_path, catalog)]:
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n')
    import sys
    sys.path.insert(0, str(root/'scripts'))
    from update_catalog import render_readme
    render_readme(catalog)


def main() -> None:
    assets = ROOT/'assets'
    assets.mkdir(exist_ok=True)
    native = ROOT/'branding/app-icons'
    native.mkdir(parents=True, exist_ok=True)
    report = {'scope':'Repository branding only; existing IPA bytes are unchanged.', 'apps':{}}
    for bundle, (name,tint,previous) in BRANDS.items():
        image = render(name, 1536).resize((1024,1024), Image.Resampling.LANCZOS)
        image.save(native/f'{name}.png', optimize=True)
        # Catalog artwork uses the same geometry with the rounded mask from the preview.
        icon = image.convert('RGBA')
        mask = Image.new('L', image.size)
        ImageDraw.Draw(mask).rounded_rectangle((0,0,1023,1023), radius=218, fill=255)
        icon.putalpha(mask)
        icon.save(assets/f'{name}.png', optimize=True)
        report['apps'][bundle] = {'name':name,'previousName':previous,'icon':f'assets/{name}.png','nativeIcon':f'branding/app-icons/{name}.png','tintColor':tint,'sha256':hashlib.sha256((assets/f'{name}.png').read_bytes()).hexdigest()}
    synchronize(ROOT)
    (ROOT/'branding/verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Published catalog branding for Facet, Veil, Lucid, and Echo. Prism and Music preserved.')

if __name__ == '__main__':
    main()
