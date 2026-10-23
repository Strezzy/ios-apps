# Velvet

A native SwiftUI camera and encrypted media vault for iPhone. Offline by design, with a bundled multimodal retrieval model and no accounts, analytics, cloud inference or runtime model downloads.

<img src="Velvet/Resources/Assets.xcassets/AppIcon.appiconset/Velvet.png" width="144" alt="Velvet's ivory faceted aperture on a burgundy gradient">

Version **0.2.0 (3)** updates the camera controls, Photos library and Search. The burgundy aperture icon and bundle identifier remain unchanged.

## Download

[Download Velvet.ipa](https://github.com/Strezzy/ios-apps/releases/download/velvet-0.2.0-build3/Velvet.ipa) from the [0.2.0 (3) release](https://github.com/Strezzy/ios-apps/releases/tag/velvet-0.2.0-build3). The download becomes public after native CI and screenshot review; the workflow first prepares a draft. The release includes source, the generated Xcode project, build/test reports and checksums.

Requires iOS 27.0+. Sign the unsigned IPA with your existing sideloading setup. The bundle identifier is still `com.billy.velvet`, and the storage format is unchanged. Update the existing installation and retain its data container to keep your photos, videos and settings.

## Changes in 0.2.0

- The camera keeps its viewfinder and controls in a fixed layout while control glyphs rotate with the phone. Capture orientation is tracked separately.
- Selecting video configures the live camera before recording. The rear camera prefers 4K at 60 fps when supported; the front camera prefers 1080p at 30 fps. Other lenses or devices use an available mode, and the controls display the actual selection.
- Camera controls have clearer spacing, lens choices, format/frame-rate selection and recording feedback.
- **Photos** replaces the Vault tab label, with a dense thumbnail grid, photo/video filters, album covers, simple counts and selection tools. Favorites, albums, duplicates and Recently Deleted remain available.
- Search uses a plain description field, suggestion buttons and a matching thumbnail grid. Similar-item browsing uses the same layout.

## Implemented foundation

- AVFoundation camera preview and original HEIF/JPEG capture, capability-gated RAW + JPEG, physical lens/front camera selection, tap focus, exposure bias, manual ISO/shutter and white-balance gains, flash, timer and grid.
- Real H.264/HEVC SDR recording using encoded in-memory fragmented-MP4 segments. The only app-owned movie writes are authenticated ciphertext. An AVAsset resource loader decrypts bounded byte ranges for AVPlayer.
- Random per-item AES-256-GCM keys wrapped by a random master key protected by Keychain user presence and ThisDeviceOnly access. Encrypted originals, thumbnails, catalogue, notes, search features, video manifest and segments; Complete file protection and backup exclusion.
- Face ID/device passcode authentication, lifecycle concealment/locking, screen-recording concealment, transactional metadata and authenticated catalogue recovery.
- Lazy gallery, photo/video detail, metadata/notes, favorites, albums, multi-select, exact duplicate detection, manual Trash, still-photo import and encrypted backup/restore.
- Bundled Google EmbeddingGemma 2 Text-Vision 440M with in-memory Universal Embedder input. Encrypted vectors plus Vision labels, OCR, colors and visual features. No plaintext SQLite index. Video search currently uses cover frames.
- Native navigation, tab bars, toolbars and Liquid Glass controls. Artwork extends the Facet/Veil/Lucid/Echo faceted app family.

## Build

Toolchain: Xcode 27.1 / iOS 27.1 SDK, iOS 27.0 deployment, Swift 5 language mode with minimal strict concurrency. CI uses GitHub's `xcode-27` arm64 runner and records the actual toolchain in every release. XcodeGen generates the project from `project.yml`.

Run these commands from this project's `Velvet/` directory in the `ios-apps` repository. The **Build, test and prepare Velvet release** workflow builds and tests the app, captures the interface and prepares a draft release. Publication follows review of the rendered screens.

```sh
brew install xcodegen
python3 scripts/audit.py
bash scripts/build.sh
bash scripts/test.sh
```

The build fetches one pinned 387,710,976-byte model and verifies SHA-256 before bundling. MediaPipe is pinned to commit `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb`. Model/runtime license text ships in the app; see [AI integration](docs/AI.md). No increased-memory entitlement or signing secrets are used. `Build/Velvet-unsigned.ipa` is the signable output; source build downloads need connectivity, installed app features do not.

## Security and limitations

Read the [threat model](docs/THREAT_MODEL.md), [camera capability matrix](docs/CAMERA.md), [AI integration report](docs/AI.md), [security report](docs/SECURITY_REPORT.md) and [verification procedure](docs/VERIFICATION.md). Screen captures, compromised operating systems, framework-private memory/caches and physical flash erasure cannot be fully controlled. Explicitly selected system Photos/Files assets may be cloud-backed; source Photos media remains in Photos.

Advanced HDR/Dolby Vision, Log/Log 2, ProRes/ProRes RAW, 100/120 fps, Live Photos/depth, external recording, live coaching, video-moment search and plaintext sharing are not enabled. Video search currently compares cover frames.

## Testing evidence

The published release includes its verification evidence. `Build/TEST-RESULTS.json`, `Build/BUILD-REPORT.json` and interface captures are produced by the actual run and attached to the prepared release. Tests include compact, portrait, landscape and larger-text layouts without bypassing authentication.

Physical camera orientation, sustained 4K/60 recording, lens transitions, audio, playback and device performance still need verification on an iPhone. The [device checklist](docs/VERIFICATION.md) records those checks separately from simulator results.
