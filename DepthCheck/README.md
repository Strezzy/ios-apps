# Depth Check

**Another dimension. Every frame.**

A native Swift iPhone app for turning photos and videos into stereoscopic media, with Apple's Liquid Glass interface and bundled offline Core ML models.

## Install

Use the newest **Depth Check** release in [Strezzy’s Apps](https://github.com/Strezzy/ios-apps/releases), or refresh the existing source in LiveContainer / a compatible source installer:

```text
https://raw.githubusercontent.com/Strezzy/ios-apps/main/apps.json
```

The device IPA requires iOS 26 or later. SideStore signs it for your device; LiveContainer compatibility still requires testing on the phone. The source URL remains the same as your other apps.

## Convert

1. Open **Create** and choose a photo or video from Photos or Files. Files supports RAW formats recognized by Apple's decoder.
2. Choose Apple Spatial, Full Side-by-Side, Full Over-Under, Red / Cyan, Separate Eyes, or Depth Map.
3. Adjust depth strength. Settings includes convergence, eye swap, Detailed/Balanced models, memory saver, audio retention, and HEIC/JPEG/PNG photo encoding.
4. Convert, then preview, share, or save the result. Keep Depth Check open during long conversions.

Both depth models are bundled. The app uploads no media, makes no inference-server calls, and needs no model download after installation. Photos and Files may download an original from the user's iCloud account when that file is not yet local.

For a particular camera RAW file or original video, choose that file from **Files**. Photos is asked to avoid transcoding when possible, but may supply a compatible representation. Depth Check preserves the dimensions and timing of the file it receives.

## Resolution and timing

| Source 3840 × 2160 | Export dimensions | Video timing |
| --- | --- | --- |
| Apple Spatial | 3840 × 2160 per view | Original sample timestamps |
| Full Side-by-Side | 7680 × 2160 | Original sample timestamps |
| Full Over-Under | 3840 × 4320 | Original sample timestamps |
| Separate Eyes | Two files, each 3840 × 2160 | Original sample timestamps |
| Red / Cyan | 3840 × 2160 | Original sample timestamps |
| Depth Map | 3840 × 2160, estimated depth upsampled | Original sample timestamps |

The source image is never replaced by the model's small inference image. Depth is estimated on an aspect-preserving letterboxed copy, mapped back, edge-guided, and used to warp the full-resolution source. Estimated hidden backgrounds cannot recover information that the original camera never captured; silhouette/hair/transparent-surface artifacts remain possible.

There is no 1080p or 24 FPS output preset. Processing can be slower than real time without changing playback speed or dropping frames. A frame-timing hash compares every encoded presentation timestamp with the source after conversion. This also preserves fractional rates such as 59.94 and variable frame timing when representable by the source track's timescale.

The exact HEVC encoder settings are tested on the current device before the depth model loads. A device that cannot encode a requested packed width or multiview combination returns an error; it never silently scales down. Separate Eyes provides full per-eye dimensions with a less demanding individual encoder size. Physical 4K60 and headset playback validation is still required.

## Memory

The pipeline processes one frame at a time and retains one additional source frame to recover exact timing when a decoder omits sample durations. Submitted buffers are retained by the encoder and recycled only after it releases them; the renderer caps its buffer pool. No entire movie or 24-frame 4K batch is accumulated in RAM. Memory Saver clears Core Image and Metal caches every 24 processed frames while keeping one continuous output timeline. No segment seams or frame-rate conversion are introduced.

## Models

- **Detailed, default:** Depth Anything 3 Base (Core ML FP16), using the pinned community conversion by Daisuke Majima / john-rocky, based on ByteDance-Seed's Apache-2.0 DA3 Base. 504 × 504 network input with aspect-preserving padding.
- **Balanced:** Apple's Depth Anything V2 Small FP16 package. 518 × 392 network input with aspect-preserving padding.

The exact versions and SHA-256 hashes are pinned in `scripts/prepare_models.py`. Approximately 283 MB of source model data is downloaded during the build, then compiled and bundled. [Research and source links](docs/MODEL-RESEARCH.md) explain the selection, other candidates, and the limits of comparison with Spatial Media Toolkit. No definitive iPhone 17 Pro quality/performance ranking is claimed.

Video stability smooths normalization ranges with scene-cut resets. It does not average old object silhouettes into moving frames, and it is not a trained temporal video-depth network.

## Color and file formats

Video is SDR HEVC in a MOV container. HDR video is explicitly tone-mapped to SDR Rec.709. Original audio tracks are copied where the container accepts them; failures stop the export instead of silently dropping audio. RAW photos are developed at native pixel dimensions into SDR raster images. This version preserves dimensions and frame timing, not RAW sensor data, original compressed bytes, HDR dynamic range, Dolby Vision metadata, or lossless video compression.

Apple Spatial exports use spatial HEIC stereo-pair metadata for photos and multiview HEVC with two tagged eye layers for video. The camera metadata describes the synthetic virtual camera model. It does not claim that the source was physically captured with two cameras.

## Build and verify

Run **Build and publish Depth Check** in this repository's Actions tab, or on an Apple Silicon Mac with Xcode 26 or later:

```sh
cd DepthCheck
python3 scripts/build_ios.py
```

The script verifies model download hashes, compiles both Core ML packages, generates the Xcode project, builds and runs focused XCTest cases, launches the app in an iPhone simulator, captures a screenshot, builds the actual arm64 iPhone executable, signs it ad hoc, and verifies the IPA structure, platform, entry point, compiled models and Metal shaders. The GitHub workflow publishes successful builds and adds their verified metadata to the existing app source.

When the Mac exposes an MV-HEVC encoder, the same spatial-video test also runs natively against the production Swift and Metal code. It must verify both eye layers, spatial metadata, audio, and exact frame durations before packaging can proceed. The build report distinguishes native Mac, simulator, and physical-device coverage.

The workflow requires repository Contents write permission for its requested release and catalog update. No paid Apple Developer membership or distribution certificate is used by CI. SideStore provides the user's device provisioning later.

Build evidence is available with each release. A passing simulator/build test is not a physical-iPhone performance, memory-pressure, long-video, or headset playback test.

## Source and notices

The app is written in Swift; its stereo image kernels use Apple's Metal Shading Language. UI, media, inference and image coding use SwiftUI, AVFoundation, Core ML, Core Image, ImageIO, VideoToolbox, Photos and Metal. No Python runtime or third-party runtime framework is part of the app. Python only prepares the build and model files on the Mac.

Full model notices and licenses are included in the app's About screen and `DepthCheck/DepthCheckResources`. Model weights are downloaded from their pinned source repositories during CI and are not stored in Git.
