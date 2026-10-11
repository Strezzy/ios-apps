Depth Check turns photos and videos into stereo media locally on your iPhone.

- Native SwiftUI Liquid Glass interface, Photos and Files import, original-file storage, export history, share and save.
- Bundled Detailed (Depth Anything 3 Base, community Core ML conversion) and Balanced (Apple Depth Anything V2 Small FP16) models; media conversion works offline.
- Apple spatial HEIC / multiview HEVC, full side-by-side, full over-under, red/cyan anaglyph, separate eye files, and depth maps.
- Original per-eye pixel dimensions and video sample timestamps; no fixed 24 FPS or 1080p preset.
- Frame-by-frame processing, optional periodic cache clearing, depth strength, convergence and eye-order controls.

Full 4K per-eye side-by-side is 7680×2160. Each exact encoder configuration is preflighted on the device. An unsupported configuration produces an error, without reducing resolution or dropping frames; Separate Eyes may use a supported encoder size. Encoding 4K60 on a physical iPhone 17 Pro and playback on a target headset still require device validation.

HDR video is intentionally tone-mapped to SDR in this version. RAW photos are developed to raster image output; the original source is kept. Original pixel dimensions are preserved, while estimated depth is inferred at the model's smaller input size and used to warp the original image. Monocular synthesis can show artifacts around newly exposed backgrounds and fast motion; video stabilization is not a trained video-depth model.

The included build report records the actual build/test results. The IPA is an arm64 iPhone build with an ad-hoc signature for a signing/sideloading installer or LiveContainer. SideStore supplies your device signature. No App Store installation or physical-device test is implied.
