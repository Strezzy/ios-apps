# Rift voice mode

Voice is turn-based and entirely local after language-model setup. Tap the waveform beside the composer, then Talk. Tap Send when finished, or enable Hands-free turns to send after a pause and listen again after the spoken reply. Pause, dismissal, audio interruption, device disconnection, or backgrounding stops the session.

## Architecture

Apple `SpeechTranscriber` and `SpeechAnalyzer` transcribe a maximum 45-second PCM recording. On-device availability and installed language assets are checked first. Only the explicit Prepare speech language action calls `AssetInventory.assetInstallationRequest` and `downloadAndInstall`. There is no server recognizer, hosted speech endpoint, or FoundationModels-based reply replacement. The selected Rift model generates the reply. `AVSpeechSynthesizer` speaks the final answer with an installed Apple system voice. Model thinking blocks and fenced code are not read aloud.

Microphone access is requested only after Talk. Short audio is written to an excluded-from-backup temporary directory with file protection and deleted after use or cancellation. Recognized text is saved in the conversation like typed input. The voice is synthetic. System voices, rate and pitch can be changed; this is not voice cloning.

## Short-clip voice cloning

Not shipped in 1.3. Apple's Personal Voice creation is a separate Settings workflow for the user's own voice, not a three-second general cloning API. Pocket TTS demonstrates a plausible lightweight cloning approach, but the inspected Swift/Core AI port specifically uses the without-voice-cloning checkpoint; other iOS ports advertise built-in embeddings. A working clip-conditioning and audio pipeline needs separate on-device integration and validation. No recordings are uploaded for this feature.

## Device validation still required

CI checks compilation, UI/state/cancellation, text cleanup, animation pixels, and existing model inference. It does not establish actual microphone operation, installed SpeechTranscriber assets, transcription quality, Bluetooth routing, acoustic echo or silence detection on a physical iPhone or LiveContainer host. Voice mode reports unavailable speech support rather than falling back to the cloud.

## Sources reviewed

- https://developer.apple.com/videos/play/wwdc2025/277/
- https://developer.apple.com/documentation/speech/speechanalyzer/analyzesequence(from:)
- https://developer.apple.com/documentation/speech/assetinstallationrequest
- https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer
- https://support.apple.com/104993
- https://kyutai.org/pocket-tts-technical-report/
- https://github.com/RahulRachuri/pocket-tts-swift
