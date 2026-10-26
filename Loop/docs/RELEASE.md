# Loop 2.0.0 (build 9): more power, simpler controls

## Easy first, detailed when needed
One-tap cinematic looks, saved looks, clear subject selection and editable effect cards replace the need for a crowded studio timeline. Advanced timing, mask repair, lighting and output controls stay in expandable sections. Existing projects, full-length imports, crop tracking, privacy overlays and exports remain available.

## Select, track and refine
Tap an object with bundled SAM2 selection, add/remove selection points, name up to three subjects and track them across the clip. The existing appearance-checked tracker supplies each subject's path; SAM2 refines its edges at render time. Paint keep/remove corrections that follow the tracked box. Incomplete tracks block scoped export instead of silently following an unrelated subject. This is not SAM2's recurrent video predictor or guaranteed re-identification through complete occlusion.

## Depth, portraits and environments
Bundled Depth Anything V2 estimates relative depth for layered weather, distant fog, focus blur and approximate directional lighting. Optional optical-flow-assisted stabilization reduces mask/depth discontinuities. Analyze camera movement once to anchor weather to a 2D translation path. Six editable cinematic presets combine existing photographic backgrounds, weather, color and portrait treatments.

A bundled 478-point MediaPipe face model improves facial placement and supplies expression scores. Hair segmentation, hair recolors, lip and iris colors and a smile-reactive treatment join source-pixel face/body reshaping. Background protection estimates pixels exposed by body reshaping. These are local compositing/reshaping tools, not full scene reconstruction, cloth replacement or realistic synthesis of hidden content.

## Make it move
Find suggested loop endpoints, add an overlap crossfade, freeze a subject or freeze its surroundings, and add up to three motion echoes. The overlap loop is shorter and silent; reverse/ping-pong keep their existing behavior. A still frame must be selected for cinemagraphs. Fast motion, disocclusion and moving cameras can reveal seams or frozen-background holes.

## Mix and save
Stack up to twelve editable effects, including several from the same category. Scope supported effects to people, backgrounds or tracked subjects. Set start/end times, fades and strength points. Save reusable looks locally and import 3D .cube LUTs. Shape preparation precedes backgrounds and grading; this is not an arbitrary node compositor.

## Export
GIF, APNG, H.264 and HEVC remain. Optional stable GIF palettes reduce color flicker and enable changed-region encoding. Transparent APNG and HEVC-with-alpha MOV remove the detected background. HEVC offers a floating-point-to-10-bit HLG export path for HDR source video, subject to encoder support. This does not preserve Dolby Vision metadata. Display-range LUTs and some stylistic effects can compress HDR highlights. Previews remain SDR; assess HDR exports in an HDR-capable viewer. Transparent video support varies by viewer.

All models and resources ship with the app, with no runtime downloads, account or cloud processing. The larger offline model bundle increases installation size. Complex masks, depth and neural effects may substantially slow preview/export. Physical-iPhone speed, thermals and long 4K exports remain to be measured; no real-time 4K guarantee is made.

Validation reports identify the exact compiled source and actual focused test results. Update the existing com.billy.loop installation and retain its data container.


### Coordinate and runtime safeguards
Tensor masks, hair/feature masks and bitmap readbacks follow Core Image top-first memory rows without duplicate vertical flips. Native regression checks cover known mask positions, half-precision tensor channels, real hair placement and translated images. Flat selection outputs are rejected rather than treated as the entire frame. An invalid accelerated SAM execution retries the complete pipeline using the CPU and retains that safer backend; no replacement mask is fabricated. When Vision dense-flow model assets are unavailable, bounded global translation alignment is used; this is not dense non-rigid flow or recovered 3D motion.


### Selection-model numerical compatibility
The bundled SAM2 mask decoder has one algebraically equivalent local graph change: `pow(x, 2)` is expressed as `mul(x, x)`. Learned weights are unchanged. Both original and patched graph hashes and the unchanged weight hash are recorded in `SCENE-MODELS.json`; `scripts/patch_sam_square.py` reproduces the transform. The native release tests must validate real subject masks before publication. Nonfinite model outputs are rejected, never converted into a whole-frame selection.
