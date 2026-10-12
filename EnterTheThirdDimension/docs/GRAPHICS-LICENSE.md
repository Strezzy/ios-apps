# Graphics and shader licensing

Reviewed on October 12, 2026 for **Enter the Third Dimension**.

## What this build uses

The game uses an original WebGL renderer, original GLSL transformation effects,
and original character and environment art. The courier continues the original
Moonhop character: amber hood, teal coat, coral scarf, satchel, and boots.
The sprite grids in `Resources/Game/art.js` are generated entirely from local,
deterministic pixel drawing instructions. Their palette entries are opaque RGB
colors; a dot marks an empty cell.

No source code, generated shader code, artwork, or presets from
`shader-effects-inc/shaders` are included. No shaders.com premium content is
used. The graphics code has no third-party rendering-engine dependency and
does not initialize the Shaders library or its telemetry. Research links below
record an evaluated alternative; they are not a dependency declaration.

## The evaluated repository permits commercial use

The upstream [LICENSE](https://github.com/shader-effects-inc/shaders/blob/main/LICENSE)
is the MIT License, with copyright **2026 Shader Effects Inc.** It permits use,
modification, redistribution, sublicensing, and sale. If code or substantial
portions of that software are included in a future build, its copyright and
permission notice must accompany them. The license does not require making
the game's own source public or paying a royalty.

The repository's [README](https://github.com/shader-effects-inc/shaders#readme)
expressly covers the engine, every component, and framework bindings. The
[platform license, version 2.0](https://shaders.com/license), effective
October 6, 2026, confirms that the repository and npm software are governed
by MIT and that its commercial grant controls. Thus, that software's license
allows inclusion in a paid game. Apple App Review is a separate process;
this assessment makes no claim of App Store approval.

The shaders.com design platform, presets, collections, and sections have
separate terms. A public preview is not permission to copy Pro content. We
used none of those assets or exports.

## Why the library is not included

Source inspection used commit
[`81fd4ece5d493ca6c424a2af41f0e2c361ec8258`](https://github.com/shader-effects-inc/shaders/tree/81fd4ece5d493ca6c424a2af41f0e2c361ec8258).
The relevant effects are WebGPU-oriented TypeScript definitions, composed
through the library's standard primitives and TypeGPU, with generated WGSL.
They are not standalone GLSL programs for our WebGL renderer.

| Inspected component | What it does | Relevance to this game |
| --- | --- | --- |
| [ChromaticAberration](https://github.com/shader-effects-inc/shaders/blob/81fd4ece5d493ca6c424a2af41f0e2c361ec8258/packages/core/src/shaders/ChromaticAberration/index.ts) | Samples a child texture at different RGB offsets. | An RGB split can accent the transformation, but does not create depth. |
| [Ripples](https://github.com/shader-effects-inc/shaders/blob/81fd4ece5d493ca6c424a2af41f0e2c361ec8258/packages/core/src/shaders/Ripples/index.ts) | Generates animated concentric color rings. | Useful as an effect category; the game has its own implementation. |
| [RippleWipe](https://github.com/shader-effects-inc/shaders/blob/81fd4ece5d493ca6c424a2af41f0e2c361ec8258/packages/core/src/shaders/RippleWipe/index.ts) | Reveals or hides child content through radial alpha bands. | Does not supply camera rotation, volumetric characters, or depth collision. |

The actual 2-D-to-3-D mechanic requires geometry, a changing camera, a
volumetric player, and movement and collisions along the depth axis. Original
effects integrated into the same rendering context suit that small game
without adding a second graphics pipeline.

At the inspected commit, `packages/shaders/package.json` identifies
`shaders` version `4.0.4` and a dependency on `typegpu` version `0.12.3`.
The core workspace additionally declares `colorjs.io` `^0.5.2`. Framework
peers are optional, so using the library's JavaScript entry would not itself
require React. Any future adoption should pin the actual distribution and
retain notices for every dependency that is shipped.

The inspected [telemetry entry point](https://github.com/shader-effects-inc/shaders/blob/81fd4ece5d493ca6c424a2af41f0e2c361ec8258/packages/core/src/telemetry/index.ts)
accepts `disableTelemetry`, and the
[collector](https://github.com/shader-effects-inc/shaders/blob/81fd4ece5d493ca6c424a2af41f0e2c361ec8258/packages/core/src/telemetry/collector.ts)
can send performance information to `shaders.com/api/telemetry`. This code
is not present in the game. A future offline integration would need to
disable or remove it before initialization and verify the bundled result.

## Apple rendering support and the compatibility choice

WebKit's [Safari 15 release article](https://webkit.org/blog/11989/new-webkit-features-in-safari-15/)
documents WebGL 2 support on iOS 15 and WebGL rendering over Metal.
The [Safari 26.0 release article](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/)
documents WebGPU support on iOS 26, its WGSL shading language, and its closer
mapping to modern graphics hardware. The
[Safari 27.0 release article](https://webkit.org/blog/18325/webkit-features-for-safari-27-0/)
continues to document improvements to both WebGPU and WebGL.

WebGPU is therefore a valid modern Apple-platform technology. The choice
here is based on integration size and compatibility with the existing app
host, rather than an assumption that current iPhones lack WebGPU or that
WebGL is inherently faster. A future WebGPU path should feature-detect
`navigator.gpu` and successfully request an adapter in the actual bundled
WKWebView build, using the shipping resource-loading configuration. Safari
support alone is not a substitute for testing that host.

## Attribution for this build

Because this build includes no upstream Shaders implementation or assets,
there is no Shaders copyright notice to redistribute with its graphics.
The links in this document are voluntary research references. If future
work copies or adapts upstream code, record the exact revision and include
the complete required license notice in the distributed app, with a
readable third-party acknowledgments view where appropriate.
