# LumaLift

Native SwiftUI video enhancement for iPhone and iPad. Pastel pink and lavender, real Liquid Glass controls, and no app-initiated networking.

## What it does

Enhancement, output size and frame rate are separate controls. Restore a 1080p/30 video while keeping 1080p, add 60 FPS motion, or select 2x/4x resolution within the output limits. The interface includes Photos/Files import, adjustable strength, a real two-second processed preview, original/processed playback, progress, pause/cancel, thermal protection, a local library, sharing and explicit saving to Photos.

Real-ESRGAN General x4v3 runs through Core ML with pretrained weights. Its 256-pixel input tiles include 40 pixels of context on each edge. Each output tile is cropped and reduced directly to 1x/2x/4x without allocating a full 4x intermediate video frame. At 1x this is **AI restoration followed by downsampling**, not a dedicated native-1x model. The strength blends restored pixels with the original. With enhancement disabled, upscaling still uses AI at a lighter fixed strength.

RIFE 4.26 runs through MPSGraph and Metal at the original frame dimensions, before spatial processing. A timestamp-based output clock supports 24-to-60, 30-to-60 and variable-frame-rate input without changing playback duration. Only a small number of video buffers are retained. Conservative cut detection avoids interpolating large transitions; it can also skip interpolation during flashes or very fast motion. This is framewise enhancement, not a temporally trained video restoration model; some footage may show flicker or invented texture.

## First-release boundaries

- iOS/iPadOS 26 or newer. Physical iPhone validation is still required; simulator tests are not phone performance measurements.
- Standard-color SDR video only. HDR, Dolby Vision and wide-gamut clips are rejected rather than silently misinterpreted.
- Output is capped at 3840x2160, including portrait. AI motion requires input no larger than 1920x1080 pixels, including portrait.
- Original FPS, 30 FPS and 60 FPS are offered. No 120 FPS mode or real-time speed claim.
- Output: high-bitrate H.264 in MOV. Original audio tracks are passed through when enabled. This can produce large files.
- Keep the app open. Work pauses for backgrounding and heat. Resume works in the current process, not after an app termination or device restart.
- Export validation checks dimensions, duration, encoded frame count/order and audio-track presence. It does not prove perceptual quality or validate every possible media format.

## Privacy

The app has no accounts, telemetry, advertising SDKs or network requests. Both pretrained models are inside the IPA, including at first launch. Source videos are copied into private working storage; original files are never overwritten or deleted. The local library is excluded from device backups. Users explicitly control saving and sharing. OS Photos/Files pickers may retrieve cloud originals, and saving to a cloud-enabled destination may sync via that service. Choose already-downloaded local inputs for fully offline operation. This editor does not anonymize visible or audible content.

## Build

The macOS GitHub Actions workflow builds the physical-device app, then runs native simulator tests that execute both actual models and an end-to-end enhancement plus 60 FPS export. Publication and the existing app-source update are blocked unless those tests and package checks pass.

On a Mac with Xcode 26+, Python 3.11 and XcodeGen:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install numpy==1.26.4 torch==2.5.0 coremltools==8.3.0 pillow==11.1.0
python scripts/prepare_models.py
python scripts/build_ios.py
```

Build preparation fetches **public upstream source and model weights only**, never user media. The RifeMetal source is pinned to `1fef4869a44fca32848102b9f6a774a20eb50db6`; its host-targeted shader plugin is replaced with Xcode destination-aware resource compilation. Inference mathematics and weights are unchanged. The build records weight hashes, package-file hashes and Core ML/PyTorch parity in `MODEL-PROVENANCE.json`. The upstream Real-ESRGAN release asset is versioned and its retrieved SHA-256 is recorded, rather than claiming a pre-existing independent hash verification.

The unsigned arm64 IPA is for the user's existing sideloading workflow. It is not an App Store submission or a developer-signed distribution.

## Tests and release evidence

`BUILD-REPORT.json` identifies the exact SDK, source revision, tests, conversion error, IPA checksum and the explicit physical-device limitation. A simulator launch screenshot, icon, source archive and SHA-256 file accompany successful releases. `apps.json` is changed only after a valid release exists; unrelated app entries are preserved.

## Upstream references

- Real-ESRGAN: https://github.com/xinntao/Real-ESRGAN (BSD 3-Clause).
- RifeMetal: https://github.com/cinemore/rife-metal (Apache 2.0).
- Practical-RIFE: https://github.com/hzwer/Practical-RIFE (MIT weights; notice bundled by RifeMetal).
- Apple Liquid Glass: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views

All third-party license texts are bundled with the built app. LumaLift-owned source is MIT-licensed.
