# Music 0.12 (13)

This release repairs the CD-case integration introduced in 0.11 and enlarges the Albums grid.

## What was wrong

Some native playback and animation flags were boxed from C logical expressions. They serialized as JSON numbers (`1`/`0`), but the renderer accepts booleans (`true`/`false`). As a result, it ignored those commands. Browser-only tests supplied real JavaScript booleans and missed the native integration bug.

The renderer also depended on WebKit loading a script from the app bundle's filesystem path, and its static placeholder could remain above the live WebKit view while waiting for a first-frame message. The new startup path reads the bundled script in the app process and injects it into an in-memory, network-blocked page. Artwork encoding no longer blocks initial commands or rendering. Startup and renderer failures are reported rather than silently presenting the placeholder as a working 3D case.

## Corrections

- Explicit JSON booleans for spinning and animated lid/tilt commands.
- Actual 3D CD-case geometry and the original optical shaders remain bundled locally, including the clear plastic, reflections and spinning artwork disc.
- Open/Close, press-and-hold inspection, drag-to-tilt and album browsing continue to use the native controls.
- Disc spin follows play/pause in Now Playing. Motion input reaches the renderer through the native bridge.
- Two larger album cases per row, narrower outer margins, smaller gaps and a tighter camera fit. Up to six visible grid cases can render live.
- A visible loading/failure status, bounded startup timeout and recovery after a WebContent-process termination.
- Existing native Liquid Glass navigation, themes, lyrics, Cask settings, playlists and library data paths are retained.

## Actual verification

The attached reports and screenshots come from native iOS simulator applications importing the production Music code. They exercise the real Open Case and Close Case buttons, native dragging, spinning, pause/resume, artwork changes, renderer startup and the complete Albums screen. These are not generated mockups or browser-only substitutes.

The device IPA is compiled using Apple's SDK and checked for its bundle ID, version, architecture, code signature, archive integrity and bundled-renderer checksum.

Physical iPhone testing, real sensor calibration, sustained thermal/frame-rate measurements and the user's specific LiveContainer installation remain device tests. The simulator motion test sends controlled motion values through the production native bridge; it does not claim to measure a physical gyroscope.

## Update

Refresh the existing Strezzy's Apps source and install **Music 0.12 (13)** over the existing Music entry. Keep its current data container. No new source URL is required. The bundle identifier remains `com.billy.glassmusic`.

The IPA is ad-hoc signed for a compatible signing/sideloading installer. Requires iOS 16 or later; native Liquid Glass requires a supported newer iOS version.

CD visuals: Ann Nguyen / TypingMind. Three.js and its MIT license, spectral-function credit, and existing Ryan Nair / Ryan Petrich Cask acknowledgments remain included in the app and source.
