# Speech and dialogue

[Wiki index](../AGENTS.md) · [OBS consumer](../obs/AGENTS.md) · [Verification](../tests/AGENTS.md)

- `speech.py` accepts 20 ms frames of 16 kHz mono signed PCM. It uses WebRTC VAD decisions with pre-roll and a short onset vote. An utterance ends after configurable quiet. Long utterances emit 20-second recognition chunks but still wait for the final pause before publishing cards.
- `__main__.py` reads the physical mic independently from OBS. The inference worker runs faster-whisper in process with bounded backpressure. On capture overflow, discard the broken utterance.
- `dialogue.py` atomically replaces the snapshot on the same filesystem. Each UTF-8 line contains Unix seconds, a session-scoped page ID, and one page of text separated by tabs. Normalize whitespace before writing. Keep at most 12 pages and expire entries after 20 seconds. The OBS reader deduplicates IDs. A blank file clears queued pages.
- Remove known non-speech cues such as `[BLANK_AUDIO]` and `[inhales]` before splitting text into pages. Preserve unrecognized bracketed text and skip utterances made up of cues. Match the behavior of [native cards](../macos/App/DialogueCards.swift).
- Keep PCM in memory. The snapshot is local and normally cleared on exit. Model files are cached by the upstream library. Keep logs free of recognized speech.

Sources: [faster-whisper (MIT)](https://github.com/SYSTRAN/faster-whisper), [WebRTC VAD wheels](https://github.com/daanzu/py-webrtcvad-wheels), [python-sounddevice (MIT)](https://github.com/spatialaudio/python-sounddevice).
