# Enter the Third Dimension 2.2 (4)

A visual polish update for **The Folded Forest**, the adventure of a living
raindrop that remembers the creatures it touches.

## Characters and animation

- More detailed, expressive chibi inhabitants: layered irises, glossy
  catchlights, eyelids, brows, noses and cheeks; distinctive braids, buns,
  bobs, costumes, and small accessories.
- Gentle breathing, blinking, head turns, and independent hair, outfit, ear,
  throat, and tail motion give the forest inhabitants more life.
- Sculpted water forms with a clearer silhouette. The girl has curved bangs,
  flowing locks, shaped cheeks, rounded hands, and a petal-like hem. The frog
  crouches on haunches with webbed toes, and the fox has four paws, a muzzle,
  pointed ears, and a broad moving tail.
- Pearly glass-like water shading combines captured-scene refraction,
  thickness absorption, warm highlights, cool reflections, caustic filaments,
  drifting internal bubbles, and elastic motion.
- A closer camera shows the characters more clearly. Dimensional and form
  changes draw the camera in as luminous ribbons orbit the gathering drop.

## Rainforest and lighting

- Richer forest shapes, curved trunks and roots, layered foliage, animated
  leaves, flowers, moss, glowing mushrooms, and polished lantern details.
- A continuous rear bank under solid land and a softly edged earth path give
  the playable route a more natural connection to the forest.
- New per-fragment materials distinguish skin, hair, fabric, leaves, bark,
  rock, and soil. Warm directional light and cool fill give shapes volume.
- Soft dynamic shadows include the actual animated water mesh, so the shadow
  follows her shape, jump, and floating transformation.
- Gaussian bloom, restrained light shafts, a character-centered ripple, and
  edge smoothing complete the image. Full effects support up to 2× pixel
  ratio; reduced effects use a lighter resolution and shadow map.
- Spatial scenery culling keeps off-camera geometry out of the drawing passes.

## The adventure

The opening story, girl/frog/fox memory forms, 2D-to-3D depth puzzles, lost-light
quest, twelve optional shards, lantern checkpoints, and landscape touch
controls are included. Existing saved chapter progress remains compatible.
All game resources are bundled for offline play.

## Build and evidence

The app uses the established UIKit/WKWebView host compiled against Apple's
actual SDK. Publication requires an actual native simulator launch, a live
rendered water character, completed shadow/bloom/edge-smoothing passes, and
verified arm64 iPhone packaging. Native launch evidence, a simulator capture,
source, and checksums accompany the IPA. Browser QA evidence is included in
`docs/WEBKIT-QA.json` in the source archive.

This release establishes the next visual direction; physical iPhone frame
pacing, thermal behavior, and longer device playtesting remain to be measured.

The graphics and shaders are original. The previously reviewed Shaders
library, separately licensed website presets, and external rendering engines
are not shipped.

Version **2.2**, build **4** · iOS **16.0+** · Landscape iPhone and iPad.
Bundle ID `com.billy.moonhop` is preserved. This GitHub IPA is ad-hoc signed for
sideloading; it is not an App Store distribution-signed submission.
