# Music 0.13 (14)

CD-case loading, small-cover rendering, and tilt-framing polish for the offline music player.

## Changes

- Reuse a bounded pool of initialized renderers when returning to albums or Now Playing instead of rebuilding the graphics page each time. Idle renderers stop animation and expire after 20 seconds; memory pressure clears the cache.
- Reveal the live case only after the renderer confirms the correct album artwork. A short crossfade replaces the abrupt static-to-animated pop-in.
- Render the album grid at up to 2x pixel density, use supported multisample anti-aliasing on the actual geometry targets, and increase small-case reflection and refraction detail.
- Add a small transparent rendering margin and pose-aware camera framing so tilted case and lid corners stay in the artwork area without covering labels, playback controls, or the native tab bar.
- Preserve the approved native Liquid Glass dock, five tabs, mini-player, album tile layout, themes, library and playlist data paths.

## Validation

The [native iOS build and tests](https://github.com/Strezzy/ios-apps/actions/runs/38342559912) passed 26 renderer checks, including Open/Close, playback spin and pause/resume, correct-artwork presentation, extreme-angle framing, warm-renderer reuse and memory-cache cleanup. The production Albums screen passed its scroll-and-return check with six visible animated cases and all five native tabs.

The native simulator reported 2x grid rendering, four-sample geometry MSAA and 256-pixel reflection environments. In the captured large-case test, an initial load took about 8.71 seconds and reuse of its initialized renderer took about 0.123 seconds. These are individual simulator measurements, not an iPhone speed guarantee. First launches still require graphics initialization; this update does not eliminate cold-start time.

Physical iPhone and LiveContainer installation, GPU memory, frame pacing, thermal behavior and actual gyroscope motion remain device checks. The attached screenshots use test artwork and were captured from the running native test applications. No test fixture library is shipped in the device app.

## Update

Refresh the existing Strezzy's Apps source in LiveContainer and select Music 0.13 (14). Replace the existing Music installation and keep its current data container. The existing source URL and bundle identifier `com.billy.glassmusic` are unchanged.

The IPA is an arm64 iPhone app with an ad-hoc signature for your sideloading installer. Minimum iOS version: 16.0. Native Liquid Glass requires a supported newer iOS version.

IPA size: 3,051,758 bytes
SHA-256: `cd18ba80388ef28165ec9ff1e2c4f51a43bf8fbf0925c62ca06a666f33d91c53`

Complete source, native test reports, loading measurements, screenshots and checksums are attached. Original CD-case and Cask acknowledgments and licenses remain included.
