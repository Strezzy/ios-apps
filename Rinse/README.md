# Rinse

Remove personal metadata from photos and videos, locally on iPhone and iPad.

Native SwiftUI with Apple's Liquid Glass. No accounts, analytics, advertisements,
network client, AI model or runtime downloads. iOS 26 or newer.

## Version 1

- Import photos and videos from the system photo picker, multiple Files items, or a recursively scanned folder (500-item batch limit; no symbolic links).
- Rebuild single-frame JPEG, PNG and HEIC images into fresh, full-size 8-bit sRGB rasters. Apply orientation. Use high-quality JPEG/HEIC or rendered-pixel-lossless PNG.
- Decode and re-encode ordinary SDR MOV/MP4 videos as H.264/AAC MP4, up to 4K and 60 fps, with one mono/stereo audio track. Do not copy compressed input packets, metadata tracks, chapters, subtitles or original container tags.
- Scan exported copies with ImageIO/AVFoundation. Block and delete failed outputs. Show checked field names, byte hashes and limitations. Never promise absolute anonymity.
- Optionally add 24 fresh random bytes in legal container padding: JPEG APP15, PNG private ancillary riNs, or ISO BMFF free box. This changes a cryptographic byte fingerprint, not a perceptual fingerprint. Padding never uses location, identity, source filename or source time.
- Preserve originals. Use random output names, file-protected cache storage excluded from backup, serial processing, cancellation and thermal-critical stop. Clear temporary copies manually or on next launch. Exports you save elsewhere are never deleted.
- Share verified copies or add them to Photos. A standalone, entitlement-free Share extension handles up to 10 photos, limited to 16 MP each. The main app supports photos up to 64 MP.

## Honest boundaries

The cleaner removes source metadata by reconstructing supported media, then checks
what Apple's metadata APIs expose. A zero-field report is not a forensic guarantee
against every possible hidden signal. Playback geometry, timing, codec information,
standard color profiles and optional random padding necessarily remain. Pixels,
faces, text, watermarks, voices and steganography are outside this version's scope.

JPEG/HEIC/video recompression is lossy. Photos export as SDR and do not retain HDR,
depth, spatial or Live Photo motion data. RAW, animated/multi-image photos, HDR,
wide-color, spatial and alpha videos are explicitly unsupported. Do not use a clean
copy as an archival replacement for an original.

The app itself has no network client. Apple's Photos/Files providers may download
non-local selections. For an offline-only workflow, use media already on your iPhone.
User-chosen cloud destinations and Photos iCloud synchronization are outside Rinse's
control and may attach new metadata or upload exported copies.

Keep the app open while cleaning. Backgrounding cancels an active batch. Save clean
copies before clearing the session or relaunching. Share extensions are not loaded
by every sideloading/container app; use the main app's import buttons when unavailable.

## Build and test

On macOS with Xcode 26+ and an iOS 26+ simulator:

```sh
brew install xcodegen
python3 Rinse/scripts/build_ios.py
```

The script generates the project and assets, compiles both targets, runs native
XCTest cases, launches the simulator, captures a screenshot and builds a real
arm64 iPhone IPA. It fails rather than packaging a simulator app or publishing with
missing tests. `Build/BUILD-REPORT.json` records the exact test evidence and hashes.

The GitHub workflow publishes to the existing Strezzy app source only after all
required tests pass. The IPA is unsigned; your installation tool signs it. No Apple
credentials or private certificates are stored in the repository.

Test coverage includes JPEG GPS/camera/comment removal, orientation, PNG pixel
stability with differing hashes, HEIC round-trip, cancellation, invalid input, pixel
limits, CRC correctness, video metadata removal and all-frame retention when audio
ends early. Simulator tests are not physical-device testing, a forensic audit,
App Store approval, or proof of thermal behavior for long 4K recordings.

## Source and design

Original implementation for Strezzy. Built with SwiftUI, ImageIO, Core Image,
AVFoundation, CryptoKit, PhotosUI and UIKit. XcodeGen is a build-only MIT-licensed
tool and is not included as an app runtime dependency. No code was copied from
ExifVeil, ExifCleaner or mat2.

Apple API references used for implementation:
- https://developer.apple.com/documentation/imageio/cgimagedestination
- https://developer.apple.com/documentation/avfoundation/avassetreadertrackoutput
- https://developer.apple.com/documentation/avfoundation/avassetwriter/metadata
- https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)

See LICENSE. These are passion-project, AI-assisted apps; review and test before
relying on them for high-risk privacy needs.
