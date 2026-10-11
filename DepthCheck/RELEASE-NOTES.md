Depth Check turns photos and videos into stereo media locally on your iPhone.

## Conversion reliability and steadier depth

- Fixes an end-of-stream scheduling bug in side-by-side encoding. Video and audio now signal completion even while their writer inputs are applying backpressure. An audio tail or a delayed audio start can finish without waiting for a nonexistent next video frame.
- Progress uses the video track's duration, then shows the exact decoded frame count while the writer finishes audio and video. An audio tail no longer inflates the video-work estimate.
- Corrects a depth-normalization bug that could turn arbitrary model scale/offset changes into left/right image wobble. Steadier Video Depth also filters normalized estimates in visually unchanged regions, with moving-edge and scene-cut rejection.
- Conversion errors offer **Copy Details** with app/build, conversion settings and writer state. A writer timeout no longer incorrectly tells users that Memory Saver must be enabled.
- Simplifies Create, Exports and Settings, removes repeated slogans, gives the app source a clear description, and makes the toolbar Privacy button open its privacy sheet.
- Requires sustained native Mac media tests before publication: a matching 874-frame/audio-tail regression, shorter audio, a three-minute 60 FPS timeline, and 920 full-4K60 frames exported as 7680 × 2160 side-by-side. Tests check exact video timing, AAC packets and the final decoded frame. The report records actual fixture dimensions and results; deterministic depth isolates the media pipeline, while separate tests run both bundled models.

Memory Saver continues to process frames with bounded buffers and periodic cache cleanup. This fix addresses track-completion scheduling without introducing segment seams or changing source resolution, frame count or timing. A three-minute full-4K conversion on a physical iPhone remains a device test; the three-minute native timeline fixture uses a smaller image, while the native full-4K fixture is about 15 seconds.

## Included features

- Native SwiftUI Liquid Glass interface, Photos and Files import, original-file storage, export history, share and save.
- Bundled Detailed (Depth Anything 3 Base, community Core ML conversion) and Balanced (Apple Depth Anything V2 Small FP16) models; media conversion works offline.
- Apple spatial HEIC / multiview HEVC, full side-by-side, full over-under, red/cyan anaglyph, separate eye files, and depth maps.
- Original per-eye pixel dimensions and video sample timestamps; no fixed 24 FPS or 1080p preset.
- Frame-by-frame processing, optional periodic cache clearing, depth strength, convergence and eye-order controls.

Full 4K per-eye side-by-side is 7680×2160. Each exact encoder configuration is preflighted on the device. An unsupported configuration produces an error, without reducing resolution or dropping frames; Separate Eyes may use a supported encoder size. Encoding 4K60 on a physical iPhone 17 Pro and playback on a target headset still require device validation.

HDR video is intentionally tone-mapped to SDR in this version. RAW photos are developed to raster image output; the original source is kept. Original pixel dimensions are preserved, while estimated depth is inferred at the model's smaller input size and used to warp the original image. Monocular synthesis can show artifacts around newly exposed backgrounds and fast motion; video stabilization is not a trained video-depth model.

The included build report records the actual build/test results. The IPA is an arm64 iPhone build with an ad-hoc signature for a signing/sideloading installer or LiveContainer. SideStore supplies your device signature. No App Store installation or physical-device test is implied.
