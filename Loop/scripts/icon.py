"""Reproducible vector artwork for Loop's native app and catalog icons."""
from pathlib import Path
import json
import cairosvg

root = Path(__file__).resolve().parents[1]
asset = root / 'Resources/Assets.xcassets/AppIcon.appiconset'
asset.mkdir(parents=True, exist_ok=True)
svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <linearGradient id="back" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#AAE9AF"/><stop offset="0.48" stop-color="#24B9A0"/><stop offset="1" stop-color="#116C72"/></linearGradient>
  <radialGradient id="light" cx="0.1" cy="0.05" r="1"><stop stop-color="#F1FFE5" stop-opacity=".5"/><stop offset="1" stop-color="#0E6871" stop-opacity="0"/></radialGradient>
  <linearGradient id="ribbon" x1="0" y1="0" x2="0.9" y2="1"><stop stop-color="#F3FFDE"/><stop offset=".44" stop-color="#D9FACD"/><stop offset="1" stop-color="#A6DAD1"/></linearGradient>
  <linearGradient id="edge" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#80C5B0"/><stop offset="1" stop-color="#287F84"/></linearGradient>
</defs>
<rect width="1024" height="1024" fill="url(#back)"/>
<rect width="1024" height="1024" fill="url(#light)"/>
<path d="M512 512C425 388 378 351 300 351C212 351 164 418 164 512C164 606 212 673 300 673C378 673 425 636 512 512C599 388 646 351 724 351C812 351 860 418 860 512C860 606 812 673 724 673C646 673 599 636 512 512" fill="none" stroke="#0A4B54" stroke-opacity=".15" stroke-width="112" stroke-linecap="round" transform="translate(0 36)"/>
<path d="M512 512C425 388 378 351 300 351C212 351 164 418 164 512C164 606 212 673 300 673C378 673 425 636 512 512C599 388 646 351 724 351C812 351 860 418 860 512C860 606 812 673 724 673C646 673 599 636 512 512" fill="none" stroke="url(#edge)" stroke-width="100" stroke-linecap="round" transform="translate(0 14)"/>
<path d="M512 512C425 388 378 351 300 351C212 351 164 418 164 512C164 606 212 673 300 673C378 673 425 636 512 512C599 388 646 351 724 351C812 351 860 418 860 512C860 606 812 673 724 673C646 673 599 636 512 512" fill="none" stroke="url(#ribbon)" stroke-width="100" stroke-linecap="round"/>
<path d="M448 416L512 512L575 416" fill="none" stroke="#A6D8BD" stroke-width="100"/>
<path d="M426 623C455 590 480 558 512 512C544 466 569 434 598 401" fill="none" stroke="url(#ribbon)" stroke-width="100"/>
<path d="M188 453C202 405 238 374 300 374C362 374 406 413 454 477M581 437C641 365 675 328 724 328C789 328 831 370 854 423" fill="none" stroke="#F4FFE7" stroke-opacity=".65" stroke-width="5" stroke-linecap="round"/>
</svg>'''
(root / 'Resources/LoopIcon.svg').write_text(svg)
cairosvg.svg2png(bytestring=svg.encode(), write_to=str(asset / 'AppIcon.png'))
(asset / 'Contents.json').write_text(json.dumps({
    'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
    'info': {'author': 'xcode', 'version': 1}
}, indent=2) + '\n')
(asset.parent / 'Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
catalog = root.parent / 'assets/Loop.png'
cairosvg.svg2png(bytestring=svg.encode(), write_to=str(catalog), output_width=512, output_height=512)
print('Rendered Loop icon at 1024 and 512 pixels.')
