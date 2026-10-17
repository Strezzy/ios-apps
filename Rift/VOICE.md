# Rift voice mode

Voice is turn-based and entirely local after language-model setup. Tap the waveform beside the composer to open an orb over the current chat and begin listening. A pause ends the spoken turn automatically. Hands-free turns are enabled initially and listen again after the spoken reply. Tap the orb to pause or interrupt and talk, or the composer’s X to close. Settings → Voice & sound contains speech, hands-free, activation sound and haptic controls. Pause, dismissal, audio interruption, device disconnection, or backgrounding stops the session.

## Architecture

Apple `SpeechTranscriber` and `SpeechAnalyzer` transcribe a maximum 45-second PCM recording. On-device availability and installed language assets are checked first. Only the explicit Prepare speech language action calls `AssetInventory.assetInstallationRequest` and `downloadAndInstall`. There is no server recognizer, hosted speech endpoint, or FoundationModels-based reply replacement. The selected Rift model generates the reply. `AVSpeechSynthesizer` queues stable, sentence-aware phrases as text arrives with an installed Apple system voice. Automatic selection ranks natural voices in the selected language by Premium/Enhanced quality, then dialect, while preserving explicit selections. Sentence-aware chunking and short punctuation pauses preserve phrasing. Downloading a Premium or Enhanced voice in iOS Settings can improve quality; this app does not claim a new neural voice engine. The mic is off during playback; tap the orb to interrupt. No acoustic barge-in or wake word is used. The native clear Liquid Glass orb changes its outline with mic levels while listening and word callbacks while speaking. Reduce Motion/Low Power Mode keep it still; Reduce Transparency uses material. A locally synthesized 950 ms opening glass chime finishes before the microphone starts and respects Silent Mode. An 800 ms lower closing tone rings out on dismissal. Continuous soft haptics fade over 580 ms on opening and 480 ms on closing; both sound and haptics can be disabled in Settings. Model thinking blocks, fenced code and Markdown link destinations are not read aloud. A phrase queue emits each stable span once, holds partial markup, flushes the final tail and waits for both generation and playback to end before enabling the microphone again. Closing, stopping or interrupting cancels owned generation and queued speech. Normal preparation stays visually quiet; actionable setup and error messages remain available.

Microphone access is requested when opening the orb, once a chat model and on-device speech assets are ready. Short audio is written to an excluded-from-backup temporary directory with file protection and deleted after use or cancellation. Recognized text is saved in the conversation like typed input. The voice is synthetic. System voices, rate and pitch can be changed; this is not voice cloning.

## Short-clip voice cloning

Not shipped in 1.6. Apple's Personal Voice creation is a separate Settings workflow for the user's own voice, not a three-second general cloning API. Pocket TTS demonstrates a plausible lightweight cloning approach, but the inspected Swift/Core AI port specifically uses the without-voice-cloning checkpoint; other iOS ports advertise built-in embeddings. A working clip-conditioning and audio pipeline needs separate on-device integration and validation. No recordings are uploaded for this feature.

## Device validation still required

The 1.8 CI scope covers compilation and ten focused checks of attachments, drawer navigation, downloaded-model selection, composer behavior, keyboard layout and connected orb lifecycle. The background rendering check passed in the preceding navigation check; its code is unchanged. The passing 1.6 incremental speech and cue checks remain applicable to unchanged voice code. Only Qwen3.5 4B image understanding and its connected text fallback are checked with native inference; no other model or unrelated animation tests are rerun. Audible playback and tactile feel require a physical device. It does not establish actual microphone operation, installed SpeechTranscriber assets, transcription quality, Bluetooth routing, acoustic echo or silence detection on a physical iPhone or LiveContainer host. Voice mode reports unavailable speech support rather than falling back to the cloud.

## Sources reviewed

- https://developer.apple.com/videos/play/wwdc2025/277/
- https://developer.apple.com/documentation/speech/speechanalyzer/analyzesequence(from:)
- https://developer.apple.com/documentation/speech/assetinstallationrequest
- https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer
- https://support.apple.com/104993
- https://kyutai.org/pocket-tts-technical-report/
- https://github.com/RahulRachuri/pocket-tts-swift


## Pocket TTS and Personal Voice (1.9)

Settings → Voice & sound → Pocket TTS downloads the pinned English Core ML models and cloning encoder once. Pocket is preferred after setup; Apple remains selectable and is used before setup, for other speech languages, and after a neural speech failure. Current Pocket output uses the model's natural pace/pitch; Apple speed and pitch settings continue to apply to Apple voices.

Personal Voice accepts imported WAV/M4A/MP3 audio or a fresh microphone recording. Use 3–10 seconds of clear mono/stereo speech (5–10 recommended, maximum 20 MB). Preview the recording, enter a name, and save. Only the conditioning profile and name persist, in protected local files excluded from backup. Temporary recordings are removed after saving, discarding or leaving the screen. Saved voices can be selected, previewed and deleted. This is Rift's local voice cloning, separate from Apple's accessibility Personal Voice feature.

Speech reuses the existing stable-phrase splitter. A persistent Pocket session accepts each phrase while the LLM generates and streams 24 kHz PCM into AVAudioEngine. Listening resumes only when both generation and actual audio playback complete. Stop/close invalidates callbacks immediately and cancels synthesis asynchronously. On failure, Apple resumes from the unfinished phrase (the partial phrase may repeat). Model loading is asynchronous and warmed when voice mode opens; a stalled first audio falls back after eight seconds.

FluidAudio revision: `2d6c42ca5f3accc0faf9fee9e0fff5b9b2cf6042`. Voice asset revision: `91748676fe3c8b2eb3007b3125253bcd898202c3`. English int8 FlowLM, GPU/CPU Core ML placement; Neural Engine placement is avoided due to reported upstream compilation failures. Models are pinned, and library network access is disabled outside explicit setup. See the bundled PocketTTS-Notices.txt for model/runtime attribution.

The scoped release checks cover a real streaming-and-cloning round trip, storage/input validation, cancellation/fallback, installed Apple voices, settings and composer responsiveness. Simulator results do not establish iPhone audio quality, concurrent LLM/TTS latency, memory pressure or thermal performance.
