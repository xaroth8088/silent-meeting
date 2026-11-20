# Silent Meeting host

[Mac wiki](../AGENTS.md) · [Camera transport](../Camera/AGENTS.md) · [Audio plug-in](../Microphone/AGENTS.md)

- `SilentMeetingApp.swift` controls authorization, device selection, and the capture lifecycle. Exclude both Silent Meeting devices from the physical-input lists to avoid feedback.
- `CapturePipeline.swift` captures BGRA video and 16 kHz mono PCM on separate queues. Keep physical PCM and recognized text in memory. Only rendered video enters the camera sink.
- `SpeechPipeline.swift` uses libfvad for 20 ms speech frames and the bundled whisper.cpp model via its C API. Long phrases are decoded in chunks and published when the final pause arrives. Limit queued inference and stale dialogue.
- `FilmRenderer.swift` applies film effects using Core Image. `DialogueCards.swift` controls splits and display time. `CameraSink.swift` owns the producer-side CMIO queue and producer sample lifetimes. In launcher mode, match the OBS camera UUID and adapt BGRA output to the advertised sink format.

Sources [AVCaptureAudioDataOutput](https://developer.apple.com/documentation/avfoundation/avcaptureaudiodataoutput) · [libfvad](https://github.com/dpirch/libfvad) · [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
