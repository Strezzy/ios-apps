# Rift

**Private AI. On your terms.**

A native SwiftUI local chatbot with crimson/garnet Liquid Glass, a small device-organized uncensored model catalog, and soft animated replies.

## Features

- Streaming local conversations, saved history, search, copying, regeneration, Markdown/code display, and transcript export.
- Native Bloom reply rendering: new glyphs fade, gently lift, and settle with a slight spring. A bounded presentation buffer smooths uneven model output without delaying inference. Saved text does not replay. Reduce Motion and Low Power Mode use lighter effects; Soft Fade and Instant are also available.
- iPhone-first model picker, including iPhone 18 Pro and Pro Max, then compact model groups including Heretic, Qwen and Gemma. Two featured choices keep each group small; Show all options exposes other sizes. Small benefit badges explain the tradeoffs.
- Explicit model downloads with pinned revisions, byte sizes and SHA-256 checks; pause/resume; compatible single-file GGUF imports from Files.
- No account, analytics, remote inference, or chat uploads. Network access is for explicit model downloads. Inference is always local; there is no offline switch or cloud fallback. Opening a source link or selecting a cloud-backed Files item is a user action.
- Actual-memory preflight, context limits, cancellation, background release and thermal handling. Device profiles are browsing recommendations, not guarantees that an app's available memory equals the phone's installed RAM.

## Curated models

The reviewed candidates are Qwen3.5 2B/4B/9B Uncensored Aggressive, Gemma 4 E2B/E4B Uncensored Aggressive, and LFM2.5 2.6B Heretic Uncensored. Heretic options also include Qwen3 8B, Qwen3.5 9B, and Qwen3 14B in Compact IQ3_XS and Precision IQ4_XS quantizations. The 14B options are explicitly experimental and depend on available app memory. Only explicitly uncensored variants are eligible. An unavailable or unverifiable candidate is excluded, never silently replaced by a stock aligned model.

Uncensored describes the publishers' community modifications. It cannot guarantee zero refusals or unchanged capabilities. Rift does not add a content-filtering layer, refusal rewriting, or remote moderation. Custom imports keep their own behavior and are marked unverified rather than falsely certified uncensored. All model licenses remain in force.

The catalog was researched October 14, 2026. The model authors' primary sources are:

- https://huggingface.co/HauhauCS/Qwen3.5-2B-Uncensored-HauhauCS-Aggressive
- https://huggingface.co/HauhauCS/Qwen3.5-4B-Uncensored-HauhauCS-Aggressive
- https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive
- https://huggingface.co/HauhauCS/Gemma-4-E2B-Uncensored-HauhauCS-Aggressive
- https://huggingface.co/HauhauCS/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive
- https://huggingface.co/noctrex/LFM2.5-2.6B-heretic-uncensored-GGUF
- https://github.com/p-e-w/heretic

Newer Ornith 1.5 9B variants and Qwen3.8 releases were also checked. An uncensored label or newer upload date is not comparative phone-performance evidence. Large 27B models and full-weight MoE models were not selected merely for headline benchmark scores. Initial catalog choices prioritize supported native architectures, manageable complete weights, distinct alternatives, and reproducible tests rather than an unverified 'best model' claim.

## Build and verification

Run the **Build, verify and publish Rift** GitHub Actions workflow. It builds pinned llama.cpp revision `8345f333951c661d166b00e6f9362e553768f292`, native simulator tests, the iPhone Metal runtime, and an arm64 iPhone app. Every catalog entry must pass actual macOS CPU inference before publication. Model weights are downloaded separately, not bundled.

On a Mac with Xcode 26+, XcodeGen, CMake, Python 3.12 and Pillow 11.1.0:

```sh
python3 Rift/scripts/build.py
```

Bundle identifier: `com.billy.rift`. Minimum OS: iOS 26. The IPA carries an ad-hoc signature with requested memory entitlements; the user's installer supplies the final device signature and provisioning. Version-specific reports under `Verification/` and in each release record actual results and remaining gaps. A successful compile or CPU smoke test is not evidence of iPhone Metal performance, long-chat stability, thermal behavior, or LiveContainer compatibility. Those require physical-device testing.

## Animation implementation

`RevealSchedule.swift` preserves Unicode grapheme clusters and bounds the presentation lead to 180 ms. `StreamingText.swift` uses native SwiftUI TextRenderer, not a WebView or a separate view for every letter. It draws settled runs normally and applies effects only to arriving glyphs. The same renderer powers the clearly labeled animation preview in Settings. Tests cover bursts, catch-up, corrections, stops, emoji, and history restoration.

Native API reference: https://developer.apple.com/documentation/swiftui/textrenderer
Device reference: https://www.apple.com/iphone-18-pro/specs/

## 1.2 interaction fixes

Reply styles now have a live inline preview which replays when changed. The streaming text renderer deliberately disables native selection during rendering, restoring selectable text once the reply settles. Regression tests compare rendered image pixels for Bloom, Soft fade and Instant.

Chat scrolling distinguishes user gestures from keyboard/layout changes. Focusing the composer follows the latest reply, and viewport resizing reanchors after layout. The full long-chat case, incoming wrapped text and rotation are tested, not only the composer frame.

There is no Offline mode switch: inference is always local. The removed preference is migrated so an old value cannot block explicitly requested downloads.

### Memory readings and LiveContainer

Remaining app memory is the current `os_proc_available_memory()` result, not total RAM or the full process limit. The estimated process budget adds `task_vm_info.phys_footprint`; it is a changing snapshot, not a guaranteed allocation. The app does not infer a granted entitlement from its packaged request.

Rift retains the increased-memory-limit and extended-virtual-addressing requests. With LiveContainer, guest entitlements are not applied to the host. Enabling the capability on the actual host App ID and reinstalling/re-signing that host may raise the available budget on supported devices. Do not delete the host's data. Standalone Rift requires the capability on its own signed app. Extended virtual address space is not more physical RAM.

Primary references:
- https://developer.apple.com/documentation/os/os_proc_available_memory
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit
- https://github.com/LiveContainer/LiveContainer#limitations
- https://github.com/hugeBlack/GetMoreRam#how-to-use

The debugger-only keyboard sample is not compiled into the distributed application and is never used as a substitute for model inference.
