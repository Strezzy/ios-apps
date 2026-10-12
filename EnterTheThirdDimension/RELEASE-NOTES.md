# Enter the Third Dimension 2.0 (2)

The next version of the Moonhop game is a short story adventure about finding
a new direction in a paper world.

## New in this build

- Enter the third dimension: the camera turns, the world reveals its depth,
  and the pixel courier gains volume.
- Flat characters and paper obstacles remain flat. Step around the first wall
  and explore a hidden bridge behind the broken road.
- Play Chapter I, **The Folded Forest**: find the prism, recover a lost spark,
  light the village gate, and collect up to twelve optional shards.
- The left/right touch pad unfolds into a depth thumbstick. Jump and movement
  work together, with adjustable jump height, forgiving edge jumps, and
  lantern checkpoints.
- New forest geometry, original character animation, moonlight, aurora,
  fireflies, restrained glow and ripple effects, and original synthesized sound.
- Pause, reduced-effects and sound settings, local saved progress, and safe
  return-to-2D checks that prevent folding into obstacles or unsupported space.

## Build and graphics

Compiled using Apple's actual SDK and the established UIKit scene/window
launch flow. Publication requires an actual native simulator launch, a
completed WebGL frame, and verified arm64 iPhone packaging. Build evidence
and checksums are attached to this release. Physical iPhone playtesting remains
the next validation step.

All game art and shaders in this build are original. The suggested Shaders
repository was reviewed and is MIT licensed; its WebGPU runtime and separately
licensed website presets are not included. The game runs entirely offline.

Version **2.0**, build **2** · iOS **16.0+** · Landscape iPhone and iPad.
Bundle ID `com.billy.moonhop` is preserved. This GitHub IPA is ad-hoc signed for
sideloading; it is not an App Store distribution-signed submission.
