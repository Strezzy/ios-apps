# Rift voice mode

Voice is turn-based and entirely local after language-model setup. Tap the waveform beside the composer to open an orb over the current chat and begin listening. A pause ends the spoken turn automatically. Hands-free turns are enabled initially and listen again after the spoken reply. Tap the orb to pause or interrupt and talk, or the composer’s X to close. Settings → Voice & sound contains speech, hands-free, activation sound and haptic controls. Pause, dismissal, audio interruption, device disconnection, or backgrounding stops the session.

## Architecture

Apple `SpeechTranscriber` and `SpeechAnalyzer` transcribe a maximum 45-second PCM recording. On-device availability and installed language assets are checked first. Only the explicit Prepare speech language action calls `AssetInventory.assetInstallationRequest` and `downloadAndInstall`. There is no server recognizer, hosted speech endpoint, or FoundationModels-based reply replacement. The selected Rift model generates the reply. `AVSpeechSynthesizer` queues stable, sentence-aware phrases as text arrives with an installed Apple system voice. Automatic selection ranks natural voices in the selected language by Premium/Enhanced quality, then dialect, while preserving explicit selections. Sentence-aware chunking and short punctuation pauses preserve phrasing. Downloading a Premium or Enhanced voice in iOS Settings can improve quality; this app does not claim a new neural voice engine. The mic is off during playback; tap the orb to interrupt. No acoustic barge-in or wake word is used. The native clear Liquid Glass orb changes its outline with mic levels while listening and word callbacks while speaking. Reduce Motion/Low Power Mode keep it still; Reduce Transparency uses material. A locally synthesized 950 ms opening glass chime finishes before the microphone starts and respects Silent Mode. An 800 ms lower closing tone rings out on dismissal. Continuous soft haptics fade over 580 ms on opening and 480 ms on closing; both sound and haptics can be disabled in Settings. Model thinking blocks, fenced code and Markdown link destinations are not read aloud. A phrase queue emits each stable span once, holds partial markup, flushes the final tail and waits for both generation and playback to end before enabling the microphone again. Closing, stopping or interrupting cancels owned generation and queued speech. Normal preparation stays visually quiet; actionable setup and error messages remain available.

Microphone access is requested when opening the orb, once a chat model and on-device speech assets are ready. Short audio is written to an excluded-from-backup temporary directory with file protection and deleted after use or cancellation. Recognized text is saved in the conversation like typed input. The voice is synthetic. System voices, rate and pitch can be changed; this is not voice cloning.

## Short-clip voice cloning

Not shipped in 1.6. Apple's Personal Voice creation is a separate Settings workflow for the user's own voice, not a three-second general cloning API. Pocket TTS demonstrates a plausible lightweight cloning approach, but the inspected Swift/Core AI port specifically uses the without-voice-cloning checkpoint; other iOS ports advertise built-in embeddings. A working clip-conditioning and audio pipeline needs separate on-device integration and validation. No recordings are uploaded for this feature.

## Device validation still required

The 1.6 CI scope covers compilation and 20 focused checks of incremental speech, audio cues, chat layout, scrolling, Cipher default, background rendering and connected orb lifecycle. Model inference and unrelated animation tests are not rerun. Audible playback and tactile feel require a physical device. It does not establish actual microphone operation, installed SpeechTranscriber assets, transcription quality, Bluetooth routing, acoustic echo or silence detection on a physical iPhone or LiveContainer host. Voice mode reports unavailable speech support rather than falling back to the cloud.

## Sources reviewed

- https://developer.apple.com/videos/play/wwdc2025/277/
- https://developer.apple.com/documentation/speech/speechanalyzer/analyzesequence(from:)
- https://developer.apple.com/documentation/speech/assetinstallationrequest
- https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer
- https://support.apple.com/104993
- https://kyutai.org/pocket-tts-technical-report/
- https://github.com/RahulRachuri/pocket-tts-swift
