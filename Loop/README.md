# Loop

**Moments, on repeat.** A native, offline video-to-GIF and APNG creator for iPhone and iPad, built in SwiftUI with native Liquid Glass controls.

## Create

Import a local video from Photos or Files, choose the section to keep, and turn it into an animation. Photos and Files use Apple's system pickers; an item stored only in iCloud needs to be downloaded by its provider before offline editing. Loop itself has no network client, account, advertising, analytics, model download or watermark.

- Original, portrait 9:16, portrait 4:5, square, landscape 16:9 and landscape 4:3 crops.
- A shaded crop window on the original frame, repositioning, zoom and horizontal mirror.
- Precise trim, frame stepping, speed, reverse and ping-pong loops.
- GIF output at 1–100 sampled frames per second; APNG up to 120 FPS.
- Resolution presets through 3840 pixels, custom sizes and original resolution, bounded to 4096 pixels on the longest edge. Optional upscaling is labeled; it does not recover missing detail.
- Real 64/128/256-color GIF palette selection and dithering.
- Circular/oval and rectangular blur, pixelation and solid cover, plus emoji and text.
- Multiple timed overlays, local Vision object tracking and manual position keyframes.
- Local saved projects and exports, progress, pause/cancel, sharing and Photos export.

## Timing and quality

GIF supports a palette of at most 256 colors per frame and stores frame delays in 10 ms steps. A 60 FPS export contains 60 sampled frames per second using alternating 10/20 ms delays to preserve the average duration. Applications that clamp short GIF delays can play it slower. APNG preserves full color and finer timing, but receiving applications vary in APNG support. Neither format contains audio. Exporting more frames or larger dimensions than the source does not invent detail or interpolate motion.

Source import accepts video formats and codecs the device can decode through AVFoundation. It is not a universal decoder for all file formats or protected video. Sampling uses presentation timestamps and the source's orientation. High-frame-rate and variable-frame-rate sources can be trimmed, slowed and resampled.

GIF and APNG are written frame by frame. No complete animation is held as an array of full-resolution frames. Reverse playback retrieves frames in reverse time order, so it may take longer than forward export. Frames, tracking metadata, output buffers, the video decoder and GPU resources still need memory. A 30,000-output-frame guard prevents accidentally unbounded exports. Large, long animations can produce very large files; the preflight figures are working-memory/raw-data estimates, not predicted compressed file sizes.

## Tracking and review

Place an overlay over the subject, start tracking from the displayed source frame and scrub through the result. Coordinates are stored relative to the upright, uncropped source so changing the crop preserves the subject's path. Tracking runs entirely on device using Vision. Occlusion, fast motion and similar subjects can make it drift or fail. Interrupted or incomplete tracking requires correction before export; it never silently drops a blur mask. Manual keyframes can correct the path.

Always review the entire exported animation before sharing redacted content. Blur is a visual effect and is not an assurance that information cannot be recognized; solid cover is available when complete concealment is needed.

## Build and install

The GitHub Actions workflow `.github/workflows/loop.yml` builds an actual arm64 iPhone application, runs simulator unit and interface tests, packages `Loop.ipa`, and publishes the verified artifact from `main`. Feature branches build without creating a public release. The exact tested candidate can be promoted without rebuilding its IPA.

On a Mac with Xcode 26 or newer and XcodeGen:

```sh
cd Loop
xcodegen generate
open Loop.xcodeproj
```

Select the Loop scheme and your signing team for a personal device installation. GitHub's IPA is unsigned for distribution and needs the user's existing sideloading/signing workflow (for example SideStore). The app has no increased-memory or private entitlement requirement.

```sh
bash scripts/build.sh
bash scripts/test.sh
```

The generated reports record the source commit, SDK, architecture, bundle identity, checksum and automated test results. Simulator tests do not establish physical iPhone thermals, long 4K exports, every codec, or behavior inside a sideload host. Those remain device-validation tasks.

## Source layout

| Path | Purpose |
| --- | --- |
| `App/` | SwiftUI editor, importers, local projects, exports and native sharing |
| `Core/Models.swift` | Versionable editing data and source-relative coordinate model |
| `Core/ExportPlan.swift` | Crop geometry, timestamp scheduling and GIF timing |
| `Core/VideoEngine.swift` | Video inspection, frame retrieval and export orchestration |
| `Core/FrameRenderer.swift` | Core Image adjustments, masks, overlays and cropping |
| `Core/TrackingEngine.swift` | Local Vision tracking |
| `Core/GIFEncoder.swift` | Streaming palette quantization and GIF encoding |
| `Core/APNGEncoder.swift` | Streaming full-color animation output |
| `Tests/`, `UITests/` | Decoded-output, scheduling, geometry and real UI verification |

## Technical references

- [GIF89a specification](https://www.w3.org/Graphics/GIF/spec-gif89a.txt)
- [Apple: GIF unclamped frame delay](https://developer.apple.com/documentation/imageio/kcgimagepropertygifunclampeddelaytime)
- [Apple: tracking objects in video](https://developer.apple.com/documentation/vision/tracking-multiple-objects-or-rectangles-in-video)
- [Apple: ImageIO destinations](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/ikpg_dest/ikpg_dest.html)
- [Apple: applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [ImgPlay official feature reference](https://imgplay.net/)
