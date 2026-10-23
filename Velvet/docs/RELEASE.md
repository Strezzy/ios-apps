# Velvet 0.2.0 (3)

This update improves the camera layout, video configuration, Photos library and Search. The burgundy aperture icon is unchanged.

- The camera layout stays fixed while control glyphs rotate with the phone. Photo and video capture orientation is tracked separately from the interface.
- Video mode changes configure the live camera before recording. Rear video prefers 4K at 60 fps where the active lens and encoder support it; front video prefers 1080p at 30 fps. Unsupported combinations fall back to an available mode, shown in the controls.
- Camera controls have clearer spacing, lens choices, format/frame-rate selection and recording feedback.
- Photos has a dense thumbnail grid, photo/video filters, album covers, simple counts and selection tools. Favorites, duplicates, albums and Recently Deleted are retained.
- Search and similar-item results use the same clean grid, with straightforward labels and suggestion buttons.

## Install or update

[Download Velvet.ipa](https://github.com/Strezzy/ios-apps/releases/download/velvet-0.2.0-build3/Velvet.ipa). Requires iOS 27.0 or newer. Use your existing signing/sideloading setup for the unsigned IPA.

The bundle identifier remains `com.billy.velvet`, and the encrypted storage format is unchanged. Update the existing installation and keep its data container to retain your photos, videos and settings. The local AI model remains bundled; no model download is needed after installation.

## Verification

The release workflow requires a successful native build and test suite before preparing its draft. It captures compact, portrait, landscape and larger-text layouts for review before publication. Attached build/test reports identify the source revision, toolchain and IPA checksum; the actual automated results are appended below.

Physical camera orientation and sustained 4K/60 recording still need device verification, along with lens transitions, audio, playback and thermal behavior. Simulator results do not establish those hardware results.

HDR, Log, ProRes and 100/120 fps modes remain unavailable. Video search compares cover frames. See the [camera capability matrix](https://github.com/Strezzy/ios-apps/blob/main/Velvet/docs/CAMERA.md), [device verification checklist](https://github.com/Strezzy/ios-apps/blob/main/Velvet/docs/VERIFICATION.md), [threat model](https://github.com/Strezzy/ios-apps/blob/main/Velvet/docs/THREAT_MODEL.md) and [AI integration report](https://github.com/Strezzy/ios-apps/blob/main/Velvet/docs/AI.md).
