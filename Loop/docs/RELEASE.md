# Loop 1.1.1 — 4K tracking stability

This maintenance update addresses reports of the editor returning home and losing crop tracking after processing a 4K60 video.

- **Lower preview memory use:** native preview buffers are requested at a maximum 960-pixel longest edge, while source frame-rate behavior and full-resolution export are preserved.
- **One active decoding task during analysis:** starting crop or overlay tracking releases the preview player, output buffers, fallback generator and pending render work. The visible frame remains on screen, and the preview is recreated after analysis.
- **Save before showing the result:** completed crop tracking is written atomically before the result preview resumes. Older pending autosaves are cancelled, and the open editor receives the committed crop before its busy state ends. A failed write is shown as an error instead of an apparent success.
- **Release tracking resources promptly:** Vision's terminal-frame signal is now sent with the final request, and analysis images and temporary objects are scoped to each sample.
- **Keep errors in the editor:** tracking and save errors use the active editor's alert, avoiding competing presentations from the home screen.
- **Safe cancellation:** cancellation during preview suspension leaves the saved project intact; a late task cannot reopen a cleared preview.

Portrait subject-follow cropping, optional size-follow and independently tracked blur/pixelation/emoji remain available. The original imported video and selected high-resolution GIF/APNG export settings are preserved. Processing remains entirely local.

**Validation:** The native regression suite includes actual 3840 × 2160 H.264 video at 60 FPS. Tests verify native preview-buffer bounds, decoder release/resume, bidirectional subject tracking, final portrait rendering, editor continuity and persistence after process termination/relaunch. Additional checks cover an older pending autosave, a deterministic write failure, cancellation during setup and a 3,601-position tracking path. Reports and native 4K tracking screenshots are attached.

**Device scope:** Validation uses native builds and iPhone simulators. The reported source video and physical-device crash/memory logs were not available; the exact cause of that device's termination was not independently reproduced. Physical iPhone memory pressure, long 4K exports and sideload-host behavior still require device validation.

**Install:** Update the existing `com.billy.loop` installation using your normal signing/sideloading workflow. The attached arm64 IPA requires iOS 26 or later and preserves the app's local projects and exports. Complete source, generated Xcode project and checksums are included. Previous releases and the other apps in the repository are preserved.
