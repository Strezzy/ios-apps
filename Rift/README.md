# Rift

**Private AI. On your terms.**

Rift is a native SwiftUI iPhone chatbot with a crimson and garnet Liquid Glass interface. Messages and inference stay on the device. Model downloads are optional, explicit network requests; there is no hosted inference fallback, account, analytics SDK, or chat upload.

## The app

Open Rift, choose a model, download it once, and start a conversation. The model picker groups choices by iPhone, then by family, with at most two models inside each family. Small benefit badges explain the tradeoff without exposing a wall of quantization settings. iPhone 18 Pro and Pro Max profiles are included. The app measures actual memory before loading: choosing a different browsing profile never bypasses the device's limits.

Saved conversations, streaming replies, Markdown/code display, copying, regeneration, local search, transcript export, model removal, Files imports, download progress, pause/resume, offline mode, thermal cancellation, and memory-pressure handling are included. Chats and models are excluded from app-managed backup. The app covers the chat when inactive and stops generation when backgrounded.

## Uncensored-only curated catalog

Only explicitly uncensored community variants are included, never the stock aligned checkpoints. Current candidates are Qwen3.5 2B/4B/9B Aggressive, Gemma 4 E2B/E4B Aggressive, and LFM2.5 2.6B Heretic. The build resolves exact GGUF filenames, commit revisions, byte sizes, and SHA-256 hashes. An unavailable or unverifiable candidate is excluded, not replaced with a regular model.

**Uncensored is not a guarantee of zero refusals or unchanged quality.** Rift adds no content-filtering layer, refusal rewriting, or remote moderation request. The underlying model determines its behavior. Custom Files imports are marked unverified rather than falsely certified uncensored. All model licenses remain in force.

Every included model must pass actual macOS CPU inference before an IPA is packaged by the verification workflow. Those tests do not establish iPhone Metal speed, heat, memory use, conversation quality, or LiveContainer behavior. Device profiles and benefit badges are engineering recommendations, not comparative performance benchmarks.

## Build

Use **Build and verify Rift for iPhone** in GitHub Actions, or on a Mac with Xcode 26+, CMake, XcodeGen, Python 3.12, and Pillow 11.1.0:

```sh
python3 Rift/scripts/build.py
```

The script fetches llama.cpp at the pinned commit `8345f333951c661d166b00e6f9362e553768f292`, compiles the actual native runtime for simulator, iPhone, and macOS, runs XCTest and UI tests, performs CPU inference for every catalog entry, builds the arm64 iPhone app, and packages `Build/Rift.ipa` with reports and a source archive. Model weights are not bundled with the app or source archive.

The IPA is unsigned for the user's signing/sideloading installer. Bundle ID: `com.billy.rift`. Minimum OS: iOS 26. Do not claim App Store approval, zero-refusal behavior, or physical-device validation from a successful CI run.

## Imports

Import single-file GGUF instruction/chat models with a supported architecture and an embedded chat template. Rift validates bounded metadata, copies the model into private app storage, and records a SHA-256 digest. Unsupported architectures, split files, vision projectors, missing templates, and malformed files receive an explanation. A valid GGUF container is not proof that an arbitrary model will run well; loading and live memory checks still apply.

## Research snapshot: October 14, 2026

The small-model catalog intentionally does not include 27B Qwen3.8 or large mixture-of-experts releases whose complete weights do not fit a sensible iPhone memory budget. Larger parameter counts are not a guarantee of better on-phone results. The sources below are author/model-maintainer references, not independent performance verification:

- https://huggingface.co/HauhauCS/Qwen3.5-2B-Uncensored-HauhauCS-Aggressive
- https://huggingface.co/HauhauCS/Qwen3.5-4B-Uncensored-HauhauCS-Aggressive
- https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive
- https://huggingface.co/HauhauCS/Gemma-4-E2B-Uncensored-HauhauCS-Aggressive
- https://huggingface.co/HauhauCS/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive
- https://huggingface.co/noctrex/LFM2.5-2.6B-heretic-uncensored-GGUF
- https://github.com/p-e-w/heretic
- https://github.com/ggml-org/llama.cpp
- https://www.apple.com/iphone-18-pro/specs/

Heretic is an uncensoring method, not a separate base-model architecture. The UI groups by actual family and identifies the modification inside that group.
