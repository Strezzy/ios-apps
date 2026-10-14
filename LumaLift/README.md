# LumaLift

**First beta.** Offline video enhancement for iPhone and iPad, using native SwiftUI with pastel pink/lavender and Liquid Glass controls. iOS/iPadOS 26 or newer.

## Features

Enhancement, output resolution and frame rate are independent controls. Restore detail without increasing dimensions, choose 2x/4x upscaling, or request 30/60 FPS interpolation. Includes Photos/Files import, enhancement strength, a real two-second processed preview, original/processed playback, progress, pause/cancel, thermal safeguards, a private local library, sharing and explicit saving to Photos. Originals are never overwritten.

Real-ESRGAN General x4v3 uses pretrained weights through Core ML. Its 256-pixel tiles include 40 pixels of edge context. Each restored tile is reduced directly to the selected output size, avoiding a full 4x intermediate frame. At 1x this is AI restoration followed by downsampling, not a dedicated native-1x network. Strength blends original and restored pixels. Upscaling with enhancement switched off still uses AI at a fixed lighter strength.

RIFE 4.26 uses the pinned RifeMetal implementation through Metal/MPSGraph at source dimensions, before spatial enhancement. A timestamp-based clock implements 24-to-60, 30-to-60 and variable-frame-rate resampling without changing the intended playback duration. A conservative scene-cut guard can also skip flashes or rapid movements. This is framewise restoration, not a temporally trained video-restoration network; detail can be invented and flicker is possible.

## Validation and beta status

The device build compiles. The release workflow requires eleven passing simulator tests: settings, size limits, output clock, tile coverage, real Core ML inference, tile orientation/color, complete restoration/export at original FPS, original timing and cancellation, portrait orientation, audio timing, and a clean unavailable-GPU error. Each exported video is decoded for frame-count and presentation-order verification.

**Real RIFE inference and combined enhancement/60-FPS export are not device-validated.** Both tests remain in XCTest for a physical iPhone, but are explicitly skipped on the hosted simulator. That virtual GPU raises an Objective-C exception inside MPSGraph initialization before inference. Simulator builds reject motion instead of crashing or silently duplicating frames. The shipped iPhone IPA retains real RIFE; it is not a simulated-GPU build.

The report separately records 11 passed simulator tests and 2 pending hardware tests. Publication uses a GitHub prerelease and a Beta-labeled app-source entry, not a claim that all device tests passed. Physical performance, heat, memory, LiveContainer compatibility and long-export reliability require device testing.

## First-release limits

Standard-color SDR only. HDR, Dolby Vision and wide-color clips are rejected, not silently reinterpreted. Output is capped at 3840x2160, including portrait; AI motion input is capped at 1920x1080 pixels, including portrait. Original FPS, 30 FPS and 60 FPS are offered. Exports are high-bitrate H.264 MOV with original audio retained when selected. No real-time-speed, HDR or 120 FPS claims.

Keep the app open. Backgrounding and heat pause processing; a terminated app or reboot cannot resume the job. Try a short preview before committing to a long export. Format and frame verification does not establish perceptual quality for every input.

## Privacy

No accounts, telemetry, advertising SDKs or app-initiated network requests. Both pretrained models ship inside the IPA. Local imports and exports use private app storage; the library is excluded from device backups. Users explicitly control saving and sharing. OS Photos/Files services can retrieve cloud inputs or sync saved exports. Use already-downloaded local files for offline operation. This editor does not anonymize visible or audible identifying content.

## Build

On macOS with Xcode 26+, Python 3.11 and XcodeGen:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install numpy==1.26.4 torch==2.5.0 coremltools==8.3.0 pillow==11.1.0
python scripts/prepare_models.py
python scripts/build_ios.py
```

Build preparation downloads public source/weights only, never user media. RifeMetal is pinned to `1fef4869a44fca32848102b9f6a774a20eb50db6`. Its host-targeted shader plugin is replaced by destination-aware SwiftPM resource compilation; inference mathematics and weights are unchanged. The Real-ESRGAN release asset is versioned; downloaded hashes and Core ML/PyTorch numerical parity are recorded in MODEL-PROVENANCE.json. This is recorded provenance, not a claim of independently authenticated weights.

The workflow compiles device and simulator builds, runs supported tests, validates IPA contents, and publishes the beta with source, icon, launch screenshot, build report and checksums. Existing app versions are checked for preservation during catalog updates. App-owned source is scanned for network APIs; that check is not a network traffic capture or a complete dependency audit.

## Upstream and licenses

- Real-ESRGAN: https://github.com/xinntao/Real-ESRGAN (BSD 3-Clause).
- RifeMetal: https://github.com/cinemore/rife-metal (Apache 2.0).
- Practical-RIFE: https://github.com/hzwer/Practical-RIFE (MIT weights; upstream notice bundled).
- Apple Liquid Glass: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- Apple AVAssetReaderOutput: https://developer.apple.com/documentation/avfoundation/avassetreaderoutput/copynextsamplebuffer()

LumaLift-owned source is MIT licensed. Third-party license texts are bundled in the app. This unsigned sideloading build is not an App Store submission.
