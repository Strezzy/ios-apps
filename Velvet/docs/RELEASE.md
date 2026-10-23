# Velvet 0.3.0 (4)

This update polishes focus, zoom and Photos navigation. The burgundy palette and aperture icon are unchanged.

- Continuous autofocus is restored on startup, mode changes and lens changes. Tap-to-focus has a visible reticle and returns to continuous tracking; subject changes trigger refocusing.
- Rear lens changes use the system virtual camera and a zoom ramp when the selected format supports it, with a physical-camera fallback for incompatible modes.
- The global tab bar is removed. Open Photos from the camera thumbnail, then return with the floating glass camera button. Library and Albums share a bottom glass selector; Search is at the top of Photos, with Settings in the toolbar.
- RAW photos have a viewfinder toggle on supported cameras. Video format choices include 100/120 fps only where the camera format and encoder support them; high-rate 4K uses HEVC. Rear video still defaults to 4K60 when available.
- Camera settings use exposure steps and a reset button. Manual ISO, shutter and white balance have their own page.

## Install or update

[Download Velvet.ipa](https://github.com/Strezzy/ios-apps/releases/download/velvet-0.3.0-build4/Velvet.ipa). Requires iOS 27.0 or newer. Sign the unsigned IPA with your existing sideloading setup.

The bundle identifier remains `com.billy.velvet`, and the encrypted storage format is unchanged. Update the existing installation and keep its data container to retain your library. The local search model remains bundled.

## Verification

The workflow requires a successful native build and XCTest suite before preparing its draft. Render checks cover compact, portrait, landscape and larger-text layouts. Attached reports identify the source revision, toolchain and IPA checksum; actual automated results are appended below.

Autofocus performance, physical lens transitions and sustained 4K120 recording require verification on an iPhone. Simulator checks cannot establish hardware performance. RAW video is not implemented: the existing encrypted in-memory HLS recorder supports H.264/HEVC, and adding ProRes RAW requires a separate validated capture/encoding path. RAW photo capture saves DNG and JPEG originals separately.

HDR, Log, ProRes and RAW video remain unavailable. Video search compares cover frames. See the [camera notes](https://github.com/Strezzy/ios-apps/blob/main/Velvet/docs/CAMERA.md) and [device verification checklist](https://github.com/Strezzy/ios-apps/blob/main/Velvet/docs/VERIFICATION.md).
