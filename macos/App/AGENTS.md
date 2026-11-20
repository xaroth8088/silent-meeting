# Silent Meeting host

[Mac wiki](../AGENTS.md) · [Camera transport](../Camera/AGENTS.md) · [Audio plug-in](../Microphone/AGENTS.md)

- `SilentMeetingApp.swift` controls authorization, device selection, and the capture lifecycle. Exclude both Silent Meeting devices from the physical-input lists to avoid feedback.
- `CapturePipeline.swift` captures BGRA video and 16 kHz mono PCM on separate queues. Keep physical PCM and recognized text in memory. Only rendered video enters the camera sink.
- `PreviewThrottle` publishes the first processed frame immediately. Represent the unset deadline as `nil`. Adding an interval to a zero-valued dispatch time uses `DISPATCH_TIME_NOW`, which otherwise postpones the first thumbnail on every callback.
- `SpeechPipeline.swift` uses libfvad for 20 ms speech frames and the bundled whisper.cpp model via its C API. An active phrase ends after 600 ms without sustained voicing. A voiced frame renews that timer only when at least 10 of the last 12 frames are voiced. Keep unconfirmed short sounds in the input for Whisper to recognize or ignore and use the actual trailing quiet to trim the buffer. Long phrases are decoded in chunks and published at the final pause.
- `FilmRenderer.swift` caches the clean intertitle artwork. Each camera or card frame passes through the same animated Core Image film effects. The stronger camera contrast correction applies to camera footage.
- `DialogueCards.swift` removes known Whisper sound cues in brackets or parentheses before pagination. Preserve other bracketed text and skip utterances that only contain cues. Keep the cue behavior consistent with the [OBS companion](../../silent_meeting/dialogue.py).
- `SoundtrackSentiment.swift` warms Apple's local Natural Language sentiment tagger and scores each cleaned utterance on a separate queue. All pages from an utterance share the result. Capture requests the track when it renders and sends the first frame of that utterance. A missing or late score keeps the current track and the card renders on time.
- `CameraSink.swift` owns the producer-side CMIO queue and producer sample lifetimes. In launcher mode, match the OBS camera UUID and adapt BGRA output to the advertised sink format.

Sources [AVCaptureAudioDataOutput](https://developer.apple.com/documentation/avfoundation/avcaptureaudiodataoutput) · [libfvad](https://github.com/dpirch/libfvad) · [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
