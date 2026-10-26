# Loop 2 implementation and provenance

## Bundled upstream models

- Apple Core ML Depth Anything V2 Small F16: https://huggingface.co/apple/coreml-depth-anything-v2-small . Revision and individual SHA-256 checksums are in Resources/SceneModels/SCENE-MODELS.json. Apache-2.0. It estimates relative inverse depth, not metric distance or a 3D scene. The documented device benchmark is not a benchmark for Loop's combined pipeline.
- Apple Core ML SAM2 Tiny image encoder, prompt encoder and mask decoder: https://huggingface.co/apple/coreml-sam2-tiny . Pinned revision and checksums in the same manifest. Apache-2.0. An independent Swift adapter uses the documented image/prompt/mask interfaces. Reference examined: https://github.com/huggingface/sam2-studio/tree/0dd708d0162e8e0b8c1e447123465b4b027e8b12 . The public image demo is not a complete video tracker. Loop uses its existing bidirectional appearance-checked box tracker, then per-frame prompted masks and optional optical-flow stabilization; it does not ship SAM2 video memory inference.
- MediaPipe Tasks Vision: https://github.com/google-ai-edge/mediapipe/tree/bfafeaed685be63fbf7ace1c3fbc4bfcbbc30128 . Pinned Swift package. Face Landmarker and multi-class selfie models are bundled, not fetched by the app. Face, hair, skin and clothing analysis are local. Apache-2.0 notices and model hashes accompany the app.
- Original MODNet, Fast-AgingGAN and Poly Haven assets remain as documented in REALISM-RESEARCH.md.

## Native implementation

Vision optical flow aligns previous masks/depth in sequential frames; scene cuts, seeks and direction changes reset state. Low-confidence masks are not represented as identity proof. Mask strokes follow a tracked bounding rectangle, not a deformable object surface. Vision translation registration estimates a camera path; parallax, rotation and independently moving objects can defeat the estimate.

Metal/Core Image shaders perform depth-layer occlusion, directional relighting approximations, focus blur, background-neighbor fill and luminance-preserving cosmetics. Dense face geometry improves placement, but not every mesh vertex drives a full 3D face reconstruction. Existing Vision pose landmarks still drive body reshaping. Effects on hidden limbs or identity replacement are not invented.

Non-destructive effect cards have bounded stacking, per-subject scope and interpolated strength keys. Loop endpoint matching considers image and motion differences, then offers choices instead of claiming every clip has a seamless loop. Cinemagraphs and echoes reuse original frames. LUTs are data-only, size-limited 3D tables; presets do not execute scripts or fetch URLs.

HDR exports request source dynamic range, retain floating-point render output, and encode 10-bit Rec.2020 HLG HEVC. This is not Dolby Vision passthrough; SDR preview and display-range effects/LUTs are explicitly labeled. Alpha output uses HEVC with alpha MOV or APNG. Encoder capability errors are surfaced rather than silently exporting another format. GIF stable palettes are sampled across the clip; changed-region frames preserve previous canvas pixels.

## Validation limits

Focused native tests exercise installed models, mask orientation, shaders, selection, motion settings, HDR render precision, LUT parsing, palette/encoding and migration. Release verification checks this exact arm64 binary and its resource inventory. Physical-device quality, long 4K memory/thermal behavior, hard occlusions, all skin/hair types and the complete editor UI suite remain separate validation work. A successful model load is not proof of best-in-market visual quality.

## Runtime portability
SAM2 uses the CPU/GPU compute path and compact prompt tokens; the prompt encoder supplies its own padding token. First-tap selection can use a native foreground-instance bounding-box cue, then SAM2 refines the requested mask. Dense Vision optical flow is preferred when its OS model is available; a bounded, confidence-gated global translation estimator is the fallback. This fallback does not recover non-rigid pixel motion.


### Coordinate and runtime safeguards
Tensor masks, hair/feature masks and bitmap readbacks follow Core Image top-first memory rows without duplicate vertical flips. Native regression checks cover known mask positions, half-precision tensor channels, real hair placement and translated images. Flat selection outputs are rejected rather than treated as the entire frame. An invalid accelerated SAM execution retries the complete pipeline using the CPU and retains that safer backend; no replacement mask is fabricated. When Vision dense-flow model assets are unavailable, bounded global translation alignment is used; this is not dense non-rigid flow or recovered 3D motion.


### Selection-model numerical compatibility
The bundled SAM2 mask decoder has one algebraically equivalent local graph change: `pow(x, 2)` is expressed as `mul(x, x)`. Learned weights are unchanged. Both original and patched graph hashes and the unchanged weight hash are recorded in `SCENE-MODELS.json`; `scripts/patch_sam_square.py` reproduces the transform. The native release tests must validate real subject masks before publication. Nonfinite model outputs are rejected, never converted into a whole-frame selection.
