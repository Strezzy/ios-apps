# Loop 1.0.1 — A live, precise editor

This update improves the editing experience while preserving existing local projects, exports and the app's bundle identity.

- **Continuous scrubbing:** the video updates while the playhead is being dragged. A persistent native player finishes the current seek and follows the latest finger position, instead of repeatedly cancelling frame requests. Playback cadence follows the source frame rate and speed within display and decoding capacity.
- **Live effects:** blur and pixelation render directly in the Overlays tab. Radius, block size and shape changes are visible immediately, including during playback. Preview effect sizes scale from the same export-pixel measurements as the finished animation.
- **Precision placement:** pinch zoom up to 12×, pan and reset the view without changing the export crop. Overlays remain at their exact source positions after zooming out. Small layers support dimensions down to 0.5% of the source.
- **Direct layer controls:** selecting a layer replaces the Add menu with its controls. Tap empty video or Done to return to adding layers. The video stays visible above the controls. A clear X on the selected overlay removes it; toolbar Undo can restore it.
- **Every emoji:** a persistent native text field opens the system Emoji keyboard when enabled, with the system keyboard as fallback. Skin tones, flags and joined emoji sequences are preserved. Keyboard Done returns to the editor.
- **Less hunting:** all overlay types appear in a visible grid, with timing and tracking in expandable sections. Center and Reset size actions help recover a layer's position and dimensions. The editor adapts to landscape and keyboard entry.

Photos and **Files** import, GIF/APNG conversion, portrait/landscape crops, resolution/FPS controls, tracking, manual keyframes, local projects and sharing remain available. Everything is processed on device, with no accounts, ads, watermark or uploads.

**Install:** `Loop.ipa` is an arm64 iPhone/iPad package for the existing signing/sideloading workflow. Requires iOS 26 or later. Update the existing `com.billy.loop` installation to retain its local data; no uninstall is needed.

**Format limits:** GIF uses 10 ms delay steps and some viewers clamp short delays. APNG supports finer timing and full color. Both formats are silent. Output remains capped at a 4096-pixel longest edge and 30,000 frames. Supported source codecs depend on the device. Cloud-only input needs to download through its provider before offline use.

**Validation:** The attached reports identify the native arm64 build and its simulator test results. New regression checks cover live scrubbing on a real 60 FPS source, live effects, preview orientation, zoom-coordinate stability, tiny layers, deletion/undo and the native emoji keyboard. Native editor screenshots are attached. Physical-device FPS, thermals, long high-resolution exports and sideload-host behavior have not been measured in this build session.

Complete source, the generated Xcode project and checksums are attached. Other apps and historical releases are preserved.
