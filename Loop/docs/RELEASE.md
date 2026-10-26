# Loop 1.3.1 (build 8): rebuilt portrait and atmosphere effects

## Finishing fixes

Edge expansion and contraction now operate locally on the matte boundary, without raising empty background or making an opaque subject translucent. Weather uses a spatial particle neighborhood instead of evaluating the entire particle set for every output pixel. Face edits are composed before body deformation, so the transformed face follows the body. Foreground stabilization responds immediately to a changed stability setting. These refinements retain the new model-based effects described below.

## Replaced, not repainted

The illustrated face masks and flat body silhouettes from 1.2 are removed. The existing cinematic grades, lens looks, crop and overlay tools, video exports and full-video import default remain.

Face presets now deform the source image: face width, jaw, chin, eyes, nose and lips, plus edge-preserving skin smoothing, detail and tone. Each has adjustable controls. Mature and Older use a bundled, converted Fast-AgingGAN Core ML model. Youthful Retouch is explicitly a retouch preset, not trained age regression. Automatic face blur and pixelation are available; review detections before relying on privacy protection.

Body presets use pose-guided source-pixel reshaping for waist, shoulders, hips, torso, arms and legs. They do not paint a body-shaped texture over the subject, invent clothing, or reconstruct hidden limbs. Strong shape edits can distort nearby scenery.

## Cleaner foreground separation

Studio quality uses bundled MODNet portrait alpha matting, source-guided edge refinement and motion-gated temporal stabilization. Accurate native matting remains available. Foreground-object mode can protect salient non-person objects. Edge, feather and stability controls plus preview-only mask inspection help with difficult clips. Seeking and changing direction reset temporal state rather than reusing an unrelated silhouette.

## Layered atmosphere and photographic backgrounds

All ten atmosphere effects use the new GPU renderer, including soft rain streaks, depth-scaled snow, embers, fireflies, confetti, refractive bubbles, volumetric-style fog and light leaks. Choose layered, behind-subject or foreground placement and adjust density, size, speed and wind. Rear particles are occluded by the foreground mask. This is layered compositing, not full 3D scene reconstruction.

Six CC0 photographic backgrounds from Poly Haven join the retained background collection. Photographic backgrounds support framing and zoom; background blur, exposure and warmth can be adjusted. The six embedded photographs are 2560 x 1440 perspective projections of original 4K HDRI assets. Imported photos retain the existing up-to-4096-pixel support.

## Offline, exports and compatibility

All shaders, models and photographic assets are bundled. No account, runtime downloads or server rendering. Existing GIF/APNG/MP4/HEVC output, audio rules, trimming, crop tracking and overlay timing remain. New video imports still select the complete clip. Old projects continue to open; retired illustrated-effect identifiers are ignored, while other edits are preserved.

Neural aging processes a 512-pixel face crop, then composites it into the source-resolution frame. It does not generate native-4K facial detail or guarantee an exact age, identity preservation, flicker-free motion or real-time playback. Heavy effects can reduce preview rate and slow export. HDR sources still export as SDR.

## Verification

The release requires native arm64 compilation and package verification, plus a separate focused XCTest run covering shaders, source-pixel warps, foreground occlusion, deterministic animation, bundled models, migration and photographic assets. A real portrait fixture also exercises detection, matting and rendering. Reports record actual results. The long full-editor UI suite and physical-iPhone validation are not claimed. Model conversion parity checks ran with native Core ML on macOS. Full provenance and limitations are in `docs/REALISM-RESEARCH.md`.

Update the existing `com.billy.loop` installation and retain its data container to keep projects and exports.
