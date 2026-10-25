# Loop

**Moments, on repeat.** A native, offline video-to-GIF and APNG creator for iPhone and iPad, built in SwiftUI with native Liquid Glass controls.

## What's new in 1.1.2

On **Overlays**, **Start here** and **End here** now control the selected overlay's appearance and disappearance at the displayed video frame. Its active time range is shown beneath the playhead and in the Timing section. With no layer selected, the buttons ask you to select one. Other tabs keep using these buttons to trim the clip. Existing position keyframes are retained; extending a tracked layer beyond its analyzed interval requires another track or review.

Subject and overlay tracking now check the selected region's appearance and movement before accepting Vision's next box. Analysis follows the source cadence up to 60 samples per second. A bounded search tries to recover the original subject after brief obstruction, and uncertain frames do not replace its appearance reference. Ambiguous or unresolved tracking still leaves the previous saved path intact. Crop and overlay paths remain independent and can be combined. Re-run **Track subject** or an overlay's **Track** to apply the new tracker to an existing project.

This release uses a native arm64 Release build and package verification only, as requested by the app owner. The lengthy simulator unit/interface suite was not run; the attached validation report states that explicitly. Subject crossings and timing behavior will be tested on the owner's iPhone. The full test command remains available for a later run.

## What's new in 1.1.1

This maintenance release addresses crop-tracking completion and saving on high-resolution sources, including 4K60 video.

- The preview now requests native buffers no larger than 960 pixels on the longest edge. It still follows the source cadence; the original video and export resolution are preserved.
- Starting crop or overlay tracking suspends and releases the preview decoder, fallback generator and pending render work before the analysis decoder starts. The visible frame stays on screen. After analysis, the preview is rebuilt in a paused state.
- Completed crop tracks are saved atomically before the editor receives the result or resumes decoding. Older pending autosaves cannot overwrite them. The saved crop and visible editor update within the same completion transaction.
- Vision receives its last-frame signal during the final tracking request. Analysis images and temporary objects are scoped to each sample, reducing retained resources between passes.
- Tracking errors are presented by the active editor, avoiding simultaneous alerts from the editor and the home screen. A cancelled or failed save does not report a successful track.

New regressions use actual 3840 × 2160, 60 FPS H.264 video to verify bounded native preview buffers, decoder suspension/resumption, bidirectional tracking and completion inside the editor. The interface test terminates the process without pressing Done, reopens the app and verifies that the saved crop still follows its subject. Persistence tests cover stale autosaves, write failures, cancellation during suspension and a 3,601-position track. These simulator checks do not establish the cause of any specific physical-device termination without its diagnostic report.

## What's new in 1.1.0

**Start here** and **End here** now sit immediately below the video, to the right of the player controls, and stay visible on every editor tab. They use the frame actually displayed on screen. The trim sliders pause and show the boundary being adjusted.

Playback updates its native start/end limits whenever the trim changes. Play at the final source frame restarts the selected clip, and the preview continues across forward, reverse and ping-pong boundaries. Continuous scrubbing and live overlay adjustment remain available.

The Crop tab can now **follow a selected subject**. Choose portrait, landscape or another crop, tap Choose subject, move and resize the subject box, then tap Track subject. Analysis runs locally over the selected clip in both directions from the visible anchor frame. The crop follows the subject's position, and **Follow subject size** can zoom out as the subject approaches or zoom in as it recedes, within the source image and framing limits. A small temporal smoothing pass reduces crop jitter without changing the existing overlay tracker.

Crop tracking is separate from every overlay's motion path. A moving crop can be combined with independently tracked blur, pixelation, covers, emoji and text. Source coordinates are mapped into the moving crop for both preview and export. Export dimensions stay fixed while the crop moves. Turn Follow subject off to return to manual framing; the stored path remains available to turn back on. If the selected time range extends beyond the tracked range, track it again before exporting.

The live editor from 1.0.1 is preserved: pinch to zoom the view up to 12× for precise placement, select a layer for immediate controls, tap its X to delete, use Undo to restore it, and enter any emoji through the native keyboard. View zoom does not alter source coordinates or the export crop.

## Create

Import a local video from Photos or Files, choose the section to keep, and turn it into an animation. Photos and Files use Apple's system pickers; an item stored only in iCloud needs to be downloaded by its provider before offline editing. Loop itself has no network client, account, advertising, analytics, model download or watermark.

- Original, portrait 9:16, portrait 4:5, square, landscape 16:9 and landscape 4:3 crops.
- A shaded crop window on the original frame, repositioning, crop zoom and horizontal mirror; separate pinch zoom for precise viewing and placement.
- Subject-follow cropping with optional size-follow, independent of simultaneous tracked overlays.
- Precise trim, frame stepping, speed, reverse and ping-pong loops.
- GIF output at 1–100 sampled frames per second; APNG up to 120 FPS.
- Resolution presets through 3840 pixels, custom sizes and original resolution, bounded to 4096 pixels on the longest edge. Optional upscaling is labeled; it does not recover missing detail.
- Real 64/128/256-color GIF palette selection and dithering.
- Circular/oval and rectangular blur, pixelation and solid cover, plus emoji and text, all visible live while editing.
- Multiple timed overlays, local Vision object tracking and manual position keyframes.
- Local saved projects and exports, progress, pause/cancel, sharing and Photos export.

## Timing and quality

GIF supports a palette of at most 256 colors per frame and stores frame delays in 10 ms steps. A 60 FPS export contains 60 sampled frames per second using alternating 10/20 ms delays to preserve the average duration. Applications that clamp short GIF delays can play it slower. APNG preserves full color and finer timing, but receiving applications vary in APNG support. Neither format contains audio. Exporting more frames or larger dimensions than the source does not invent detail or interpolate motion.

Source import accepts video formats and codecs the device can decode through AVFoundation. It is not a universal decoder for all file formats or protected video. Sampling uses presentation timestamps and the source's orientation. High-frame-rate and variable-frame-rate sources can be trimmed, slowed and resampled.

GIF and APNG are written frame by frame. No complete animation is held as an array of full-resolution frames. Reverse playback retrieves frames in reverse time order, so it may take longer than forward export. Frames, tracking metadata, output buffers, the video decoder and GPU resources still need memory. A 30,000-output-frame guard prevents accidentally unbounded exports. Large, long animations can produce very large files; the preflight figures are working-memory/raw-data estimates, not predicted compressed file sizes.

## Tracking and review

### Follow a subject with the crop

1. Choose the clip's start/end and a crop aspect, such as Portrait 9:16.
2. On Crop, tap **Choose subject**. Drag the subject box onto the person or object and resize it tightly enough to distinguish it from the background. Scrubbing lets you choose a clearer anchor frame.
3. Tap **Track subject**. Loop analyzes the selected clip and opens the result preview. Play or scrub the whole clip to review it.
4. Leave **Follow subject size** enabled to adapt to approach/recession, or turn it off to pan at a fixed crop zoom. Adjust the framing controls to refine the composition. Follow subject can be disabled without discarding its path.
5. Add any tracked overlays in the Overlays tab as usual. Crop and overlay tracks are independent and compose at each output timestamp, including reverse and ping-pong playback.

The crop stays inside the available image and preserves its aspect ratio. At image edges, or when a subject becomes larger than the available crop, it cannot invent missing surroundings. Size-follow can magnify source detail as a subject becomes smaller; it does not create new detail. Tracking uses the appearance of the selected region, motion continuity and a local recovery search to resist switches to nearby people or objects. Brief gaps are resolved only after a sufficiently strong match is recovered. Long obstructions, fully out-of-frame subjects or visually indistinguishable people can still break tracking; select a clearer anchor or shorten the clip and track again. A cancelled or incomplete new track is not applied. Extending the trim requires coverage of the new interval before export.

### Track an overlay

Place an overlay over the subject, start tracking from the displayed source frame and scrub through the result. While the layer is selected on **Overlays**, use **Start here** and **End here** beneath the video to set when it appears and disappears. These commands change only that layer's visibility, and preserve its position keyframes. Coordinates are stored relative to the upright, uncropped source so changing the crop preserves the subject's path. Tracking runs entirely on device using Vision and appearance checks. Occlusion, fast motion and similar subjects can still make it drift or fail. Interrupted or incomplete tracking requires correction before export; it never silently drops a blur mask. Manual keyframes can correct the path.

Always review the entire exported animation before sharing redacted content. Blur is a visual effect and is not an assurance that information cannot be recognized; solid cover is available when complete concealment is needed.

## Build and install

The GitHub Actions workflow `.github/workflows/loop.yml` builds an actual arm64 iPhone application, validates the release according to its declared scope, packages `Loop.ipa`, and publishes the verified artifact from `main`. Feature branches build without creating a public release. The exact verified candidate can be promoted without rebuilding its IPA. Normally validation requires the complete simulator unit and interface suite. The owner's requested build-only scope for **1.1.2 (5)** is recorded in `release-validation.json` and applies only to that exact version/build; future versions default to the full suite. Build-only releases attach `VALIDATION-REPORT.json` and do not attach historical test results or screenshots as new evidence.

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

Preview regressions exercise a real 60 FPS video, including continuous seeks, paused effect edits, live effects during playback, portrait orientation, trimmed ranges moved beyond the previous player limits, playback from the end frame and repeated forward/reverse/ping-pong boundaries. Crop tests cover old-project decoding, tracking geometry, scale changes, source bounds, independent overlay composition, local Vision tracking and decoded animation output. Interface tests verify the pinned trim actions, actual rendered-frame playback, subject selection and tracking, contextual layer controls, precise placement, deletion/undo, the native emoji keyboard and Files import. Published test results describe the exact release build's verification; they are not a physical-device FPS benchmark.

## Source layout

| Path | Purpose |
| --- | --- |
| `App/` | SwiftUI editor, importers, local projects, exports and native sharing |
| `Core/Models.swift` | Versionable editing data and source-relative coordinate model |
| `Core/ExportPlan.swift` | Crop geometry, timestamp scheduling and GIF timing |
| `Core/VideoEngine.swift` | Video inspection, frame retrieval and export orchestration |
| `Core/FrameRenderer.swift` | Core Image adjustments, masks, overlays and cropping |
| `Core/TrackingEngine.swift` | Independent local Vision tracking for subjects and overlays |
| `Core/CropTracking.swift` | Smoothed subject path, time-varying crop geometry and size-follow |
| `Core/GIFEncoder.swift` | Streaming palette quantization and GIF encoding |
| `Core/APNGEncoder.swift` | Streaming full-color animation output |
| `Tests/`, `UITests/` | Decoded-output, scheduling, geometry and real UI verification |

## Technical references

- [GIF89a specification](https://www.w3.org/Graphics/GIF/spec-gif89a.txt)
- [Apple: GIF unclamped frame delay](https://developer.apple.com/documentation/imageio/kcgimagepropertygifunclampeddelaytime)
- [Apple: tracking objects in video](https://developer.apple.com/documentation/vision/tracking-multiple-objects-or-rectangles-in-video)
- [Apple: ImageIO destinations](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/ikpg_dest/ikpg_dest.html)
- [Apple: applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple: smooth AVPlayer scrubbing](https://developer.apple.com/library/archive/qa/qa1820/_index.html)
- [Apple: adapting to ProMotion refresh rates](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)
- [ImgPlay official feature reference](https://imgplay.net/)
