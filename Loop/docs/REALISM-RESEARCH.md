# Loop 1.3: effects architecture and upstream research

## Shipped integrations

### Portrait matting: MODNet
- Source: https://github.com/ZHKKKe/MODNet/tree/28165a451e4610c9d77cfdf925a94610bb2810fb
- Official video checkpoint: the download identified in `demo/video_matting/custom/README.md`.
- Apache-2.0 covers repository code, models and demos; the excluded promotional GIF files are not used.
- Converted to a 512-pixel FP16 Core ML image-to-alpha model. Aspect-fit padding avoids stretching portrait and landscape footage. A source-guided refinement pass operates at render resolution.
- Loop adds motion-gated temporal blending, bounded state, and resets on seeks, direction changes, source sessions and analysis-mode changes. This is not optical-flow tracking and does not guarantee perfect hair or occlusion handling.
- Accurate native Vision matting and foreground-instance selection remain selectable alternatives. The latter can protect salient non-person foreground objects but is not a user-selected identity lock.

### Face aging: Fast-AgingGAN
- Source: https://github.com/HasnainRaz/Fast-AgingGAN/tree/f452c3afe63ccc65ac86b52f2338f8173f023925
- MIT; the license and attribution are bundled.
- Converted the supplied trained generator, not an untrained architecture. Core ML output was compared numerically against PyTorch on macOS. Checksums and conversion results are recorded in `Resources/RealismAssets.json`.
- Mature and Older use the same aging model at different strengths. They are not independently trained age targets. The model processes a padded 512-pixel face region and is composited into the full-resolution frame, with source-detail retention and feature protection.
- Youthful Retouch is a non-neural skin/proportion preset, not learned age regression. No arbitrary numeric target age or guaranteed identity preservation is claimed.

### Photographic environments: Poly Haven
- Six bundled perspective projections derived from original CC0 HDRI assets: Venice Sunset, Kiara 1 Dawn, Forest Slope, Modern Buildings 2, Studio Small 03 and Moonless Golf.
- Asset policy: https://polyhaven.com/license
- Original source URLs, output dimensions (2560 x 1440) and checksums are recorded in `RealismAssets.json`. Website thumbnails and example renders are not used.
- The app includes Powered by Poly Haven attribution. Backgrounds are embedded, with no runtime fetches.

## Research used to select the architecture

- GPUPixel: https://github.com/pixpark/gpupixel . Its face-reshape and bilateral beauty pipelines demonstrate source-coordinate distortion rather than drawn masks. Loop uses an independently written, orientation-aware Core Image Metal implementation rather than importing its OpenGL renderer or face-tracking dependency.
- MediaPipe: https://ai.google.dev/edge/mediapipe/solutions/vision/face_landmarker and https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker . Public face/pose/segmentation tasks are useful building blocks, but they are not complete commercial-quality transformation filters. Loop uses native Vision landmark/pose detection for this release and separately bundles the selected matting and aging models.
- MetalPetal: https://github.com/MetalPetal/MetalPetal . Evaluated as a GPU composition framework; a second rendering framework was unnecessary because Loop already shares a Core Image compositor between preview and export.
- Robust Video Matting: https://github.com/PeterL1n/RobustVideoMatting . Evaluated for recurrent temporal matting. Its GPL-3.0 distribution terms were not adopted for this application. No RVM code or weights are shipped.
- SAM face-age editing: https://github.com/yuval-alaluf/SAM . Evaluated as a more substantial age-editing pipeline, not represented as a ready-made lightweight iOS filter. No SAM code or weights are shipped.
- Snap Camera Kit: https://developers.snap.com/camera-kit . Not used; commercial SDK access and Lens content rights are not interchangeable with a free offline effect library.

## Native effects replacing illustrations

Face shaping modifies source pixels using local inverse warps, with face orientation, confidence and landmark stabilization. Body shaping uses visible shoulder/hip/limb joints and applies the same geometry to the person matte. Strong edits can still bend nearby scenery; hidden body parts are not reconstructed. Skin treatment uses edge-preserving filtering and feature-exclusion masks rather than indiscriminate face blur.

Atmosphere is now rendered by resolution-independent GPU fields with separate near, mid and far passes. Bubbles sample/refract the scene and add thin-film-colored highlights; rain uses soft directional streaks; snow and luminous particles have depth-scaled falloff; fog uses animated multiscale noise. A foreground matte occludes the rear passes. This is layered compositing, not recovered metric scene depth, world collision or photorealistic fluid simulation.

## Validation and limitations

Release publication requires native compilation, asset presence, package checks and the focused realism tests. Conversion parity checks and rendering checks do not establish market-leading visual quality, iPhone frame rates, thermal behavior or universal subject detection. Physical-device and real-world clips remain important. Neither downloaded user media nor network services are required for the shipped effects.
