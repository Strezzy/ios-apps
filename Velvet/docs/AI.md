# Private search implementation

Velvet indexes photos with Apple Vision and, when the release model is bundled, Google EmbeddingGemma 2 Text-Vision 440M. Both receive image bytes held in memory. The installed app has no model downloader. Search runs against decrypted records only during an authenticated vault session. Query text is not saved.

## Verified Google integration

The requested model exists. Google's [EmbeddingGemma documentation](https://ai.google.dev/gemma/docs/embeddinggemma) identifies EmbeddingGemma 2 as a multimodal retrieval model with Apache-2.0 weights. It is not a vision chatbot. The [Universal Embedder iOS guide](https://developers.google.com/edge/mediapipe/solutions/retrieval/universal_embedder/ios) explicitly supports `embed(imageBytes: Data)` and `embed(text: String)`. Velvet uses these APIs directly, not the Semantic Retriever file-path ingestion or its example SQLite database.

| Dependency | Pinned value |
| --- | --- |
| Runtime | MediaPipeTasksRetrieval, MediaPipe v1.1.1 |
| Runtime Git revision | `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb` |
| Model repository | `litert-community/embeddinggemma-2-text-vision-440m-litert-lm` |
| Model revision | `e301f74d5551b0c2641bd5cb4652a76239d5c5f8` |
| Artifact | `embeddinggemma-2-text-vision-440m.litertlm` |
| Exact artifact bytes | `387710976` (about 370 MiB) |
| SHA-256 | `92dcbea108899e5d6e30d919b0744f90d9967e80c67a4ab5503ac16d54f62eb0` |
| Output | 768 float values per image/query, L2 normalized |
| Inference limits | 256 text tokens; 70 vision tokens; 1024-pixel analysis image |
| App cache policy | LiteRT-LM `:nocache`; no stored query or decrypted image cache |

The [linked model card](https://huggingface.co/litert-community/embeddinggemma-2-text-vision-440m-litert-lm) identifies the generic CPU/GPU artifact, mixed int4/int8 quantization and Apache-2.0 licensing. Its iPhone 18 Pro measurements report approximately 196 MB text-plus-vision footprint on either listed backend; these are vendor measurements on different hardware, not Velvet measurements. Peak usage on iPhone 17 Pro, especially concurrent camera use and cold loading, needs device validation. Bundled license notices are under `Velvet/Resources/Licenses`.

An older sentence in the [Universal Embedder overview](https://developers.google.com/edge/mediapipe/solutions/retrieval/universal_embedder) still links the Gemma license. The exact selected artifact's repository metadata and the current Google model documentation both specify Apache-2.0; the artifact and its hash are pinned so a future upstream change cannot silently replace it.

## Build-time preparation

Run `python3 scripts/fetch_model.py` before generating the Xcode project. It fetches the immutable revision, verifies the exact byte count and SHA-256, and atomically installs the model into the app's resources. A failed check fails the build. The weights are omitted from Git; release packaging must include the downloaded resource. This is a permitted build-time download, not an installed-app network requirement.

`LocalSearchService.modelIsBundled` reports resource and runtime availability. If the runtime or model is absent, or model loading fails, the same service performs actual Vision indexing and local structured search. The UI must describe the active capability honestly. No fake vectors are generated. `testBundledModelPerformsRealImageInference` checks that a bundled model returns a real 768-value vector; a build without the resource skips that specific test.

## Runtime and privacy review

The pinned [Objective-C embedder implementation](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/mediapipe/tasks/ios/retrieval/universal_embedder/sources/MPPUniversalEmbedder.mm) passes NSData bytes into an in-memory C++ string view. Velvet never invokes its file-content ingestion helpers. The pinned [logging factory](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/mediapipe/tasks/cc/core/logging/factory/logging_factory.cc) returns `TasksDummyLogger`; its instrumentation hooks do not constitute an enabled telemetry uploader in this source configuration. Velvet adds no logging of inputs, raw runtime errors, index contents or queries. [LiteRT-LM configuration](https://github.com/google-ai-edge/LiteRT-LM/blob/main/kotlin/java/com/google/ai/edge/litertlm/Config.kt) documents the `:nocache` sentinel; its executor tests cover disabled weight caches.

MediaPipe's prebuilt xcframework checksums are pinned by its package manifest. Reviewing public source is not a binary reproducibility proof or a packet-capture test. On-device filesystem and network verification remains required before treating a release as security-audited. In particular, inspect OS and SDK allocations, console output, crash handling and all app-owned paths. Velvet cannot promise universal erasure of copies held by framework internals or OS memory.

## Search and indexing behavior

- A serial actor performs inference away from the main UI actor. It retains the loaded model, not a media library or query history. Call `reset()` on lock to release the runtime. Work finishing after lock must be rejected using the vault session identifier.
- ImageIO decodes a bounded, orientation-correct analysis image. A temporary JPEG exists only in RAM for model input. Captured/imported original bytes remain unchanged.
- Vision produces classification labels, recognized text, faces and a feature print. A small RGB sample estimates dominant colors, border colors and brightness. Color casts are approximate descriptors, not claims about the source of the light. Face rectangles are not identity recognition.
- `SearchDocument` stores these results and the model vector. `VaultStore` encrypts the document under its per-item key; there is no separate plaintext vector database. Metadata and embeddings are sensitive and receive the same protection as media.
- Text search combines semantic cosine similarity with whole-token label/OCR/color matching. Simple synonym normalization and photo/video filters help natural-language phrasing. Scores rank candidates; they are not calibrated probabilities. Unsupported relationships and negation can be misunderstood.
- Similar-image search compares compatible model vectors, falling back to compatible Vision feature prints. It excludes the selected reference. Byte-identical duplicate detection belongs to the vault's content digest, not this similarity score.
- Reindexing replaces a record for the same item. Corrupt inputs produce a generic error while leaving the encrypted original intact. Indexing does not run while locked. Large libraries must index one item at a time and release decrypted data between items.
- Video search currently describes its indexed cover frame only. It does not index individual moments, audio or the complete video. A match for blue lighting therefore means the cover frame resembles that description.

## Verification status and device procedure

Unit tests cover ranking, absent matches, OCR text normalization, modality filters, vector corruption, incompatible model versions, record round trips, invalid images, in-memory Vision analysis, similarity ordering and real bundled-model inference. Linux cannot execute Vision, UIKit or MediaPipe iOS tests; record actual macOS CI results separately.

On a physical iPhone 17 Pro, install a freshly built model-inclusive IPA; enable Airplane Mode before first launch; unlock, capture/import, index and search. Verify semantically related results, feature similarity and reindexing after failures. Lock/background during each stage and ensure no result or thumbnail returns into the new session. Repeat under thermal pressure and low storage, with AI indexing paused while recording. Inspect network traffic with network connectivity enabled as a separate test; offline success alone does not prove there were no attempted connections. Export the development app container and verify that app-owned records contain ciphertext only and that no SDK image, query, vector or OCR cache exists. Report memory and latency from Instruments, not from the vendor table.
