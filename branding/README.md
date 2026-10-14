# Strezzy app-suite identity

Prism is the visual reference and remains unchanged. Music is separate and is not part of this branding update.

| App | Previous name | Purpose | Accent |
| --- | --- | --- | --- |
| Facet | Depth Check | Convert photos and videos to 3D | Blue |
| Veil | Rinse | Remove photo and video metadata | Green |
| Lucid | LumaLift | Enhance and upscale video | Pink |
| Echo | VoiceGlass | Generate speech with a saved voice | Purple |

The approved family uses short names, sculpted light geometric symbols, coordinated gradients, consistent scale and lighting, and a distinct color for each tool.

`assets/` contains the rounded catalog icons. `branding/app-icons/` contains the opaque, full-bleed 1024-pixel native masters. Reproduce these assets with `scripts/suite_branding.py` using Pillow and NumPy.

Keep the existing bundle identifiers and data-container identities. Internal directory names and historical release filenames are not public product names and must not be renamed blindly. Never replace a published IPA with different bytes at the same version/build.

The catalog change does not rebuild an installed app or change existing release bytes. Native releases must consume the full-bleed masters, update their display names, increment their build numbers, and pass the normal build checks before publication.
