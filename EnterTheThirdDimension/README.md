# Enter the Third Dimension

A landscape iPhone pixel-art adventure. Walk and jump through a paper world,
then use a prism to reveal its third dimension. Your courier gains volume;
the villagers and paper barriers stay flat. Explore the depth axis to walk
around obstacles and find a bridge hidden behind the road.

This release contains **Chapter I: The Folded Forest**, a complete short
introductory chapter with a lost-light quest, checkpoints, twelve collectible
shards, and a concluding story beat.

## Controls

| Action | iPhone | Keyboard |
| --- | --- | --- |
| Move along the road | Left/right pad | Left/right arrows or A/D |
| Jump | Right jump button; hold for height | Space; hold for height |
| Enter or leave 3D | Glowing cube, after finding the prism | E or Shift |
| Move through depth in 3D | Unfolded thumbstick, up/down | Up/down arrows or W/S |
| Pause | Upper-right pause button | Escape or P |

The left/right axis continues to follow the road when the camera turns.
Up/down moves away from or toward the viewer along the depth axis. Touch
movement and jumping use independent pointers, and sliding the movement
thumb updates its direction continuously. Losing focus clears held controls.

The power can be used on solid ground. Returning to 2D checks the entire depth
segment and verifies a supporting surface on the flat plane. A blocked return
produces a brief hint without moving the player into a wall or over a gap.

## Presentation and runtime

- Original amber-and-teal pixel courier, flat NPCs, stepped forest geometry,
  floating cliffs, paper houses, moonlight, aurora, and fireflies.
- A real XYZ scene, depth-buffered geometry, an animated orthographic camera,
  and courier pixels extruded from 0.6 to 9 world units.
- Original GLSL ripple, restrained chromatic separation, and glow in the same
  WebGL context as the scene. See [graphics and licensing](docs/GRAPHICS-LICENSE.md).
- Offline bundled HTML/CSS/JavaScript in a native UIKit/WKWebView host. No
  accounts, analytics, remote assets, runtime downloads, or game dependencies.
- Fixed 120 Hz simulation, coyote time, jump buffering, variable jump height,
  automatic lantern checkpoints, and local chapter progress.
- Full/reduced effects and sound settings. System Reduce Motion initializes
  the effects preference on first launch.
- Safe-area-aware landscape layout, native lifecycle pause, WebGL context
  restoration, and a native loading screen that waits for a rendered frame.

## Build

Run on macOS with Xcode 26 or later and an installed iPhone simulator:

```sh
./build-macos.sh
```

The build generates a normal Xcode project from `Support/build_project.py`,
compiles with Apple's Foundation/UIKit/WebKit headers, launches the actual
bundled app in the simulator, and requires a successful JavaScript/WebGL
readiness report before packaging the arm64 device application.

Outputs are under `Build/`: `EnterTheThirdDimension.ipa`, a source archive,
checksums, and native build evidence. The GitHub workflow publishes them and
updates the repository's app catalog from the verified public IPA.

The current distribution package is ad-hoc signed for a sideloading workflow.
For App Store distribution, build/archive with the appropriate Apple team,
bundle registration and distribution signing. That submission is separate
from this GitHub release. The stable bundle identifier remains
`com.billy.moonhop`; app version is **2.0**, build **2**, deployment target
**iOS 16.0**.

## Source map

- `Sources/main.m`: real-SDK native app and window lifecycle.
- `Resources/Game/world.js`: world geometry, quest positions, and collectibles.
- `Resources/Game/game.js`: gameplay, collisions, input, progress, and audio.
- `Resources/Game/render.js`: WebGL renderer, camera, voxel mesh and GLSL.
- `Resources/Game/art.js`: original character sprite grids.
- `Resources/Game/index.html`, `style.css`: interface and touch controls.
- `Support/`: project generation, build verification, release publication,
  and an optional reproducible icon utility.

`window.ThirdDimension.getState()` provides read-only diagnostic snapshots.
It does not expose teleportation or mutable game state. The retained
`window.Moonhop.nativePause()` alias supports the working native lifecycle.
