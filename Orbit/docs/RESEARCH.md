# Spatial video on an iPhone

Orbit uses public Apple frameworks. Apple’s Photos-style spatial-scene presentation is not a public iOS video-player API; the documented `ImagePresentationComponent` and `Spatial3DImage` APIs are for visionOS. Orbit therefore reconstructs a depth-dependent view from the recorded stereo pair and renders motion parallax itself.

## Playback and stereo decoding

- [AVPlayerVideoOutput](https://developer.apple.com/documentation/avfoundation/avplayervideooutput) exposes the video samples from the same `AVPlayer` that renders audio. It is available on iOS 17.2 and later.
- [AVVideoOutputSpecification](https://developer.apple.com/documentation/avfoundation/avvideooutputspecification) with [`stereoscopicForVideoOutput()`](https://developer.apple.com/documentation/swift/array/stereoscopicforvideooutput()) requests the recorded left and right views. Buffers are selected by `.stereoView(.leftEye)` and `.stereoView(.rightEye)`, not by an assumed array order.
- [`taggedBuffers(forHostTime:)`](https://developer.apple.com/documentation/avfoundation/avplayervideooutput/taggedbuffers(forhosttime:)) provides synchronized stereo pixel buffers, a presentation time, and the active configuration. This API remains usable but is deprecated in iOS 27 in favor of `sample(forHostTime:)`. Using the established tagged-buffer path also supports the iOS 26 deployment target.
- [`defaultOutputSettings`](https://developer.apple.com/documentation/avfoundation/avvideooutputspecification/defaultoutputsettings) is available from iOS 18. Orbit requests full-resolution Metal-compatible BGRA color. This renderer targets SDR display; it does not claim a Dolby Vision/HDR mastering pipeline.
- [Reading multiview 3D video files](https://developer.apple.com/documentation/avfoundation/reading-multiview-3d-video-files) documents stereo detection via `.containsStereoMultiviewVideo`. The sample’s macOS sample-cursor reader is not used in Orbit’s iOS playback path.
- [`VTIsStereoMVHEVCDecodeSupported()`](https://developer.apple.com/documentation/videotoolbox/vtisstereomvhevcdecodesupported()) provides an explicit runtime capability check. Unsupported systems get immediate, labelled 2D playback. The real-media test skips on a simulator only when this capability check reports unsupported; unexpected decode failures remain failures.
- [`AVPlayerVideoOutput.Configuration.preferredTransform`](https://developer.apple.com/documentation/avfoundation/avplayervideooutput/configuration/preferredtransform) reports the source track’s orientation. Stereo matching must use the raw source coordinates; portrait/landscape display rotation is applied consistently afterward.

## Depth and presentation limits

- [Apple staff clarification: Spatial Scene API for iOS Apps](https://developer.apple.com/forums/thread/787237) states that the announced RealityKit spatial-scene APIs are visionOS-only. The current [ImagePresentationComponent documentation](https://developer.apple.com/documentation/realitykit/imagepresentationcomponent) lists visionOS availability.
- A spatial video records two viewpoints, not a complete 3D environment. It can support bounded motion parallax but cannot reveal surfaces unseen by either camera. Depth at hair, reflections, transparent surfaces, occlusion boundaries, low-texture areas, and fast motion may be imperfect. Conservative tilt and crop reduce those artifacts.
- Vertical parallax is synthesized from estimated scene depth. It is not a third camera view recorded by the iPhone. Displaying a video in portrait or landscape is independent of the orientations supported by Apple’s camera app when recording spatial video.
- Ordinary videos contain one view and play flat. Missing stereo output also falls back to clearly labelled 2D playback; Orbit does not claim to recover recorded stereo information from a flattened export.
- Apple calls [`VNGenerateOpticalFlowRequest`](https://developer.apple.com/documentation/vision/vngenerateopticalflowrequest) resource-intensive and recommends one request at a time. Orbit’s playback controller does no model downloads or per-frame Vision request queueing; depth rendering is a separate bounded GPU stage.

## Verification boundary

An Xcode build validates SDK/API compatibility. Real iPhone recordings and physical-device testing remain necessary to evaluate stereo decoding, sustained thermals, depth quality, motion calibration, and perceived playback smoothness. Simulator success cannot establish those properties.
