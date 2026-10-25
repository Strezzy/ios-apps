# Strezzy’s iPhone Apps

I'm Strezzy. These are passion projects I build for myself and share here for free. This page has my app downloads, a quick explanation of what each one does, and directions for installing and updating them in LiveContainer.

## Downloads

| App | Version | Download | Requires |
| --- | --- | --- | --- |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Music.png" width="44" alt=""/> **Music** — Offline music player | 0.15 (16) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/music-0.15-build16/Music.ipa) | iOS 16.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Echo.png" width="44" alt=""/> **Echo** — Turn text into speech with your voice | 1.1 (104) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/echo-1.1-build104/Echo.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Prism.png" width="44" alt=""/> **Prism** — Generate and edit images with AI | 1.2 (3) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/prism-1.2-build3/Prism.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Facet.png" width="44" alt=""/> **Facet** — Convert photos and videos to 3D | 1.1 (301) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/facet-1.1-build301/Facet.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Veil.png" width="44" alt=""/> **Veil** — Remove metadata from photos and videos | 1.1 (201) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/veil-1.1-build201/Veil.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Lucid.png" width="44" alt=""/> **Lucid** — Offline video enhancement · Beta | 1.1 (204) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/lucid-1.1-build204/Lucid.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Rift.png" width="44" alt=""/> **Rift** — Private offline AI chat | 1.9.7 (142) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/rift-1.9.7-build142/Rift.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Velvet.png" width="44" alt=""/> **Velvet** — Camera, photos and local search | 0.3.0 (4) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/velvet-0.3.0-build4/Velvet.ipa) | iOS 27.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Moonwake.png" width="44" alt=""/> **Moonwake** — A starlight pixel adventure | 1.0.0 (1) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/moonwake-1.0.0-build1/Moonwake.ipa) | iOS 26.0+ |
| <img src="https://raw.githubusercontent.com/Strezzy/ios-apps/main/assets/Loop.png" width="44" alt=""/> **Loop** — Offline GIF and animated PNG creator | 1.1.0 (3) | [Download IPA](https://github.com/Strezzy/ios-apps/releases/download/loop-1.1.0-build3/Loop.ipa) | iOS 26.0+ |

The number in parentheses is the build number. If the version number stays the same, a higher build number means a newer update. You can read what's changed on the [releases page](https://github.com/Strezzy/ios-apps/releases).

## Yes, they're vibe-coded

**All of my apps are vibe-coded.** I use AI tools to help write the code, while I direct development, give detailed instructions, beta test, and work through bugs and revisions. I spend **$200+ a month** on those tools and **5–8+ hours a day** on development and testing.

These are personal passion projects, shared for free. Constructive feedback is welcome. If AI-assisted development is a dealbreaker, you're free to pass. If you'd prefer a different process, you're also welcome to contribute the budget and put in the hours. The tools help with the code; the bill and the time are still mine.

## What each app does

### Music

Play music stored on your iPhone offline. Browse songs, albums, and playlists; explore interactive clear CD cases with spinning artwork; and customize themes, album art, lyrics, and scrolling animations.

### Echo

Turn typed text into speech using a short voice recording. Record or import a sample, save voices, and export clips as WAV files. Download a model before using it offline. Voice generation in this release still needs testing on a real iPhone.

### Prism

Create images from a text description, or add reference pictures and describe the edits you want. Download a model before using it offline, then save and export images from the gallery. Image generation in this release still needs testing on a real iPhone.

### Facet

Convert photos and videos into 3D on your iPhone. Export Apple Spatial, side-by-side, over-under and other stereo formats at the original pixel dimensions and video frame timing. Includes two offline depth models. HDR video is converted to SDR.

### Veil

Clean photos and videos on your iPhone without accounts, uploads or analytics. Import individual files, batches or folders; create separate copies; compare metadata reports and SHA-256 fingerprints; save or share the results. Supports JPEG, PNG and HEIC photos, and ordinary SDR MOV/MP4 videos up to 4K/60 fps. Photos export as SDR. Includes a small-batch photo Share extension where supported by your installation method. Originals are unchanged. Metadata removal does not hide visible content or prevent image matching. Physical iPhone testing is still required for this first release.

### Lucid

FIRST BETA. Restore video detail at its original resolution or upscale 2x/4x with bundled Real-ESRGAN. Native pastel pink-purple SwiftUI and Liquid Glass controls, adjustable strength, a 2-second preview, original audio preservation, pause/cancel, thermal safeguards, and a private local export library. RIFE 30/60 FPS motion interpolation is implemented and bundled in the iPhone build, but its two GPU tests require physical-device testing and are explicitly not reported as passed. Simulator tests cover restoration, exports, audio timing, orientation, cancellation and error handling. No accounts, uploads, analytics or model downloads. Standard-color SDR input only; up to 4K output and 1080p input for motion. H.264 MOV exports; originals stay untouched. Physical iPhone performance, heat, LiveContainer compatibility and long-export reliability remain unverified.

### Rift

Private offline iPhone chat with downloaded uncensored community models or an imported GGUF. Version 1.8 adds local image and file attachments from the composer’s plus button. Qwen3.5 4B image understanding uses the matching publisher vision encoder, an optional verified 676 MB download. Text and text-based PDFs are read locally. The same uncensored weights are retained, with no added content filter or cloud moderation. Includes the left conversation drawer, quick model menu, morphing composer and living crimson background. No accounts, analytics, uploaded recordings or cloud inference. Larger models and images depend on device and host memory. Version 1.8.1 fixes composer responsiveness and keeps the conversation drawer transition full height. Version 1.8.2 fixes installed-voice startup, restores liquid composer transitions, and adds a short uncensored default personality. Version 1.9 adds offline Pocket TTS streaming, Apple speech fallback, and Personal Voice import, recording and saved voice cloning. Version 1.9.1 adds floating particle history that reassembles while browsing earlier messages. Version 1.9.2 makes history particles more animated and keeps the effect active while scrolling. Version 1.9.3 adds the Q6_K download option for Qwen3.5 4B Aggressive uncensored. Version 1.9.4 reduces repeated UI and persistence work while preserving existing features and appearance. Version 1.9.5 adds a centered voice orb with reactive particles and reversible chat scattering, while suspending chat rendering during voice mode. Version 1.9.6 fixes chat visibility by limiting the voice scatter shader to individual message surfaces during transitions. Version 1.9.7 reduces voice response waits and adds a darker maroon voice scene, inward listening motion, denser rear particles and occasional neural connections.

### Velvet

Capture photos and videos, browse albums and favorites, and search your library on iPhone. Version 0.3 improves continuous autofocus and lens transitions, moves Search into Photos, and adds a bottom glass Library/Albums selector with a floating camera button. Supported cameras have a RAW photo toggle and 100/120 fps video choices, including 4K120 HEVC where available. Rear video still prefers 4K60. Camera settings use exposure steps and a separate manual-controls page. Media and search data remain encrypted on device. No accounts, analytics or runtime model download. Requires iOS 27. RAW video is unavailable; physical camera performance and LiveContainer behavior still need device validation.

### Moonwake

Explore five moonlit realms as Aster, a white-haired wanderer with a glowing starlight sword. Awaken fifteen runes, free five guardians and restore the moonwells to reach the ending. Sword combos, evasive dash, Moonpulse magic, amber spirit Wisp and moss guardian companions, hidden caches, upgrades and local saves. Original animated pixel artwork and seventeen original audio assets, native SwiftUI Liquid Glass menus, touch controls, controller and keyboard support, left-handed controls, reduced effects and Story difficulty. Built in native Swift with SpriteKit. Entirely offline, with no accounts, ads, purchases, analytics or downloads. Landscape iPhone and iPad; requires iOS 26 or later. Physical-device performance and sideload-host behavior still require device playtesting.

### Loop

Turn videos from Photos or Files into GIFs and full-color APNG animations. Follow a selected subject with a moving portrait, landscape or square crop, including optional size-follow as it approaches or recedes. Stack independent tracked blur, pixelation, covers, emoji and captions on top. Trim beside the pinned player controls, scrub continuously, preview effects live, and pinch zoom up to 12x for precise placement. Choose frame rate and resolution, reverse or ping-pong playback, and use the full system emoji keyboard. Native Liquid Glass, local projects and exports, no accounts, ads, watermark or uploads. GIF supports up to 100 sampled FPS with 10 ms timing steps; playback varies between viewers. APNG supports up to 120 FPS. Output is capped at a 4096-pixel longest edge. Requires iOS 26. Physical iPhone performance and sideload-host behavior still need device validation.

## Add my apps to LiveContainer

You only need to add this source once.

1. Open **LiveContainer → Sources → +**.
2. Paste the address below and add the source.
3. Open **Strezzy’s Apps** and tap **Install** beside the app you want.

```text
https://raw.githubusercontent.com/Strezzy/ios-apps/main/apps.json
```

You can also download an IPA from the table above and import it through **Apps → + → Install IPA File** in LiveContainer.

## Native suite rename

**The first native Facet, Veil, Lucid and Echo releases use new bundle IDs.** Keep the old installation and export important files before removing it. Data does not automatically transfer to the new app identity. See [the one-time installation note](docs/NATIVE-SUITE-UPGRADE.md). Prism and Music are unchanged.

## Update an app and keep your data

**Leave the old version installed.** Replacing that existing copy lets LiveContainer reuse its data container, where the app keeps your files and settings. Keep a separate copy of any files you can't replace before updating.

1. Open **Sources** in LiveContainer and tap the circular refresh button (**Refresh All**).
2. Open **Strezzy’s Apps** and tap **Install** beside the app you want to update. The button can still say **Install** for an update.
3. When LiveContainer finds the existing app, select that existing entry in the **Installation** prompt. It may appear as a name ending in `.app`. **Install as new** creates a separate copy.
4. Wait for the installation to finish, then open the app using the same data container as before.

**Updating with a downloaded IPA:** Download the newer IPA, open **Apps → + → Install IPA File**, and select the file. Choose the existing app entry in the installation prompt.

### If the app opens with an empty library

Check which data container is selected. If you use more than one, long-press the app in LiveContainer and choose your previous one under **Containers**. A different container can make the app look empty even when your files are still in the original one. Avoid deleting the app or clearing its data while you're checking.

These steps cover updates to an app already inside LiveContainer. Moving an app from a separate installation into LiveContainer needs its own data transfer.

## Found a problem?

[Open an issue](https://github.com/Strezzy/ios-apps/issues) with the app name, version and build number, your iPhone model, and your iOS version. Tell me what you were doing and what happened. Screenshots help when they show the problem; please keep personal files and voice recordings out of public reports.

---

[Publishing and catalog maintenance](docs/PUBLISHING.md)
