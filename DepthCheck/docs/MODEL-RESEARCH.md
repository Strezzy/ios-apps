# Depth Check: model research and implementation decision

Researched on 11 October 2026. Source links below distinguish model authors,
Apple's distribution, and community Core ML conversions. This document does not
claim a measured iPhone 17 Pro ranking; this build still needs device testing.

## Decision

Depth Check includes two real, offline models in the application bundle:

| App setting | Exact model | Why included | Source package bytes |
|---|---|---|---:|
| Detailed (default) | Depth Anything 3 Base, FP16 monocular Core ML conversion by Daisuke Majima / john-rocky | Newer, higher-capacity depth estimation with a readily inspectable native Core ML conversion | 233,541,894 |
| Balanced | Depth Anything V2 Small FP16, distributed by Apple | Established Apple-distributed package, lower memory demand, useful for longer videos and device comparisons | 49,819,122 |

Combined source packages are 283,361,016 bytes before Core ML compilation and IPA
compression. Model weights are fetched only during the build, not by the iPhone
app. The build downloads exact repository revisions, validates every file's
SHA-256 and length, and fails rather than packaging absent or substituted models.
The application also checks the expected input interface when loading a model.

The default is a practical iPhone choice, not a universal claim of best possible
depth quality. Model quality, temporal consistency, disocclusion handling, and
output encoding are different parts of the conversion pipeline.

## What Spatial Media Toolkit publicly discloses

The app matching the request is [Spatial Media Toolkit by Strange Mesa](https://apps.apple.com/us/app/spatial-media-toolkit/id6477903679).
Its [official site](https://www.spatialmediatoolkit.com/) and
[2D-to-3D explanation](https://www.spatialmediatoolkit.com/blog/2d-to-3d-video-converter)
describe local AI processing, stereo view generation, spatial exports, and VR
formats. Neither these pages nor the inspected App Store description identify a
model name, checkpoint, architecture, or training procedure.

Therefore the app's exact model is **not publicly verified** by this research. It
would be inaccurate to state that it uses Depth Anything, MiDaS, Depth Pro, or
Apple's Photos spatial-scene model. The observed 1080p/24 fps export limitation is
the user's report; the public material inspected does not establish the internal
reason for that limitation. An export cap is not evidence of a fixed depth-model
frame-rate limit.

## Models compared

| Candidate | Evidence and deployment status | License and decision |
|---|---|---|
| [Depth Anything V2 Small](https://developer.apple.com/machine-learning/models/) | Apple distributes the 24.8M-parameter FP16 Core ML package and reports 26.21 ms inference on iPhone 16 Pro. That is model inference at its small input resolution, not end-to-end 4K stereo export. | Apache-2.0 for Small. Included as Balanced. |
| [Depth Anything 3 Base](https://github.com/ByteDance-Seed/Depth-Anything-3) | The authors describe stronger monocular and multiview geometry performance. The inspected [Core ML conversion](https://huggingface.co/mlboydaisuke/Depth-Anything-3-Base-CoreML) exposes single-image depth and confidence, with ImageNet normalization embedded. The publisher lists about 700 MB peak RAM, without an iPhone 17 Pro benchmark. | DA3 Base is Apache-2.0. Included as Detailed. |
| [DA3MONO-LARGE Core ML](https://huggingface.co/sdkv2/DepthAnythingV3Mono-CoreML) | A real community conversion of the 0.35B monocular model exists: 668,468,936 source bytes, RGB 504×504 input and depth tensor. The publisher targets Apple Silicon/macOS 14+ and describes a small numerical change to positional interpolation. No verified iPhone 17 Pro performance measurement was found. | Upstream DA3MONO-LARGE is Apache-2.0. Strong candidate for a later optional high-quality model after device profiling and visual comparisons; not bundled merely on parameter count. |
| [Video Depth Anything](https://github.com/DepthAnything/Video-Depth-Anything) | Designed for temporal consistency. Small has 28.4M parameters. Authors report 6.8 GB VRAM for FP16 inference with a 32-frame, 518×518 input on an A100. Their later streaming mode reuses temporal states but is explicitly experimental, with a documented quality drop relative to offline inference. A ready, verified Swift/Core ML temporal package was not located. | Small is Apache-2.0; Base/Large are CC BY-NC 4.0. Appropriate future video-specific port, not a drop-in model to claim implemented today. |
| [Apple Depth Pro](https://machinelearning.apple.com/research/depth-pro) | High-resolution metric depth with strong boundaries; the paper reports 2.25 MP depth in 0.3 seconds on a desktop GPU. Those figures are not iPhone measurements. | The [current Hugging Face checkpoint license](https://huggingface.co/apple/DepthPro/blob/main/LICENSE) permits research purposes and excludes product development/commercial products. The GitHub repository's code/license statement differs. Do not treat this as an unambiguously licensed checkpoint for the app. Not bundled. |
| [DepthCrafter](https://github.com/Tencent/DepthCrafter) | Diffusion-based consistent video depth; substantially different inference and memory requirements from single-image Core ML estimation. | Its [license](https://github.com/Tencent/DepthCrafter/blob/main/LICENSE) excludes commercial and production purposes. Not bundled. |

Depth Anything 3's licenses are variant-specific: the main Small/Base and the
specialized Mono-Large/Metric-Large are Apache-2.0, whereas main any-view
Large/Giant and nested Giant-Large are listed under CC BY-NC 4.0. Do not infer the
license of a checkpoint from the repository's code license or a similarly named
variant. The authors prefer the refreshed `-1.1` checkpoints where offered for
main Large/Giant; those are not the Base checkpoint included here.

## Verified model interfaces

The interfaces below were checked against the actual protobuf model files, not
only README examples. The model input's resolution and the exported media's
resolution are deliberately independent.

| Property | Balanced | Detailed |
|---|---|---|
| Source repository | `apple/coreml-depth-anything-v2-small` | `mlboydaisuke/Depth-Anything-3-Base-CoreML` |
| Pinned revision | `cfef6f6f2a70783dedc0bfae40cecbc2052285d3` | `8e2e01d73a6b78f89beaac573ce3a009cf1fbb50` |
| Source package | `DepthAnythingV2SmallF16.mlpackage` | `DepthAnythingV3_base_504.mlpackage` |
| Input | `image`: RGB image, width 518, height 392 | `image`: RGB image, width 504, height 504 |
| Swift input | 32-bit BGRA `CVPixelBuffer`; Core ML handles RGB conversion | Same; scale and ImageNet normalization already in the graph |
| Depth output | `depth`: grayscale Float16 image / `CVPixelBuffer` | `depth`: Float16 `MLMultiArray`, shape `[1, 504, 504]` |
| Other output | None | `confidence`: Float16 `MLMultiArray`, shape `[1, 504, 504]` |
| Raw meaning | Relative inverse depth; larger means nearer | Relative depth; larger means farther |
| Compute units | `.all` | `.all`, matching the conversion publisher's configuration |

The [Hugging Face Swift example](https://github.com/huggingface/coreml-examples/blob/main/depth-anything-example/DepthApp/DataModel.swift)
also confirms that Apple's model returns a depth pixel buffer. The model card
contains an inconsistent prose dimension in its evaluation notes; use the
actual model interface above, not that typo.

The [DA3 Core ML conversion script](https://github.com/john-rocky/CoreML-Models/blob/master/conversion_scripts/convert_depth_anything_v3.py)
selects the monocular subgraph. Camera pose, multiview aggregation, sky refinement,
and Gaussian splat outputs from the full research system are not features of
this app. The converter fixes positional embeddings for its fixed image grid;
the Swift implementation supplies RGB input without applying a second round of
ImageNet normalization. See the publisher's
[conversion notes](https://github.com/john-rocky/CoreML-Models/blob/master/docs/coreml_conversion_notes.md)
for execution-unit and FP16 limitations.

## Rendering, source resolution, and frame rate

Depth inference runs on a smaller letterboxed copy of every input frame. The
padding is removed from the estimated depth map, and that map guides synthesis
from the original-resolution color image. This retains the source color detail;
it does not pretend that the network predicted independent geometry at every
4K or RAW-image pixel. Small structures, hair, reflections, transparency, and
newly revealed surfaces remain difficult monocular-depth cases.

The model processes every decoded frame. If 60 source frames take several
seconds to process, they still belong to the original one-second interval in
the output timeline. Source presentation timestamps determine playback speed.
The processing throughput and exported playback rate are separate numbers.

For a 3840×2160 source, a **full-resolution per-eye** side-by-side frame is
7680×2160. A 3840×2160 packed SBS frame would give each eye only 1920×2160. Full
over-under is 3840×4320. The app should never silently choose half-SBS, 1080p, or
24 fps when an encoder rejects the requested dimensions. Hardware/codec
acceptance must be checked on the actual device, and separate full-resolution
eye files remain a useful alternative when a packed format is unsupported.

Processing 24 frames at once is not necessary to retain 60 fps playback. A single
3840×2160 BGRA frame is 33,177,600 bytes before any depth map or second eye. A
24-frame color batch alone is roughly 760 MiB. Bounded, sequential frame
processing, reusable pixel buffers, writer backpressure, and timely release of
GPU resources are better memory foundations. Long exports also need thermal,
storage, cancellation, and app-lifecycle handling; model size alone is not peak
process memory.

## Implemented temporal behavior

The initial app estimates each frame with the selected monocular model. Its
temporal setting stabilizes robust depth-range scalars, uses frame appearance
change to follow motion faster, and resets on detected scene cuts or abrupt
depth-scale changes. It never blends old depth pixels into new frames, avoiding
the trailing silhouettes produced by a static per-pixel exponential average.

This can reduce depth-range pumping. It does not provide the temporal training
of Video Depth Anything and cannot guarantee flicker-free 3D. A future upgrade
should compare a verified temporal model or optical-flow-aligned depth against
this baseline, including fast motion, cuts, entering/exiting foreground objects,
and occlusions. Such an upgrade must preserve all output timestamps.

## Validation and remaining device work

The build script validates six model files against pinned SHA-256 digests.
Tests load both bundled models, predict a frame, check output finiteness and
aspect ratio, and exercise near/far direction, invalid predictions, flat depth,
scene-cut reset, and absence of pixel-history ghosting. Run these with the
project's Xcode test workflow; Linux cannot execute Core ML inference.

An iPhone 17 Pro should be measured with representative 4K60 SDR and HDR clips,
48 MP photographs/RAW input, portrait video, varying frame rates, long-duration
exports, thermal throttling, low storage, and background interruptions. Neither
this research nor a simulator build is a substitute for those measurements.
Do not publish a claim that the model is best, that export is real-time, or that
every encoder/device combination accepts 4K-per-eye 60 fps until tested.

## Attribution

Depth Anything V2 is by Lihe Yang, Bingyi Kang, Zilong Huang, Zhen Zhao, Xiaogang
Xu, Jiashi Feng, and Hengshuang Zhao. The Balanced Core ML conversion is
distributed by Apple with Hugging Face integration examples.

Depth Anything 3 is by Haotong Lin, Sili Chen, Jun Hao Liew, Donny Y. Chen, Zhenyu
Li, Guang Shi, Jiashi Feng, and Bingyi Kang / ByteDance Seed. The Detailed Core
ML conversion is by Daisuke Majima / john-rocky. Both selected model variants
carry Apache-2.0. Full license text and a model notice accompany the app's
resources. App-side cropping, reciprocal conversion, range normalization, and
stereo rendering are Depth Check integration code, not upstream model claims.
