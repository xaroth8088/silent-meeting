# Native device verification

[Mac wiki](../AGENTS.md) · [Installer](../Installer/README.md)

- The packaging script can run the native smoke tests without installing a device. Use `SILENT_RUN_TESTS=1` and set `SILENT_TEST_PCM` to a short 16 kHz mono s16le recording of “The meeting is now in session” with at least a second of trailing silence. Use public or locally generated test audio.
- `Smoke.swift` feeds the real WebRTC VAD and Whisper model, checks pause finalization and card timing, then renders sample frames and checks pixels. `DriverSmoke.c` uses the compiled HAL driver's interface to check device properties and receive actual piano PCM in process.
- On a normally secured test Mac, install the signed package, restart, enable the virtual camera, and select both devices in a separate camera/microphone app. Confirm the preview and remote camera show the same card and its expiration. Check that the virtual input contains piano while speech produces cards. Check that no physical audio reaches the virtual mic. Stop capture and confirm the camera goes to standby. Verify device selection when multiple clients use the devices.

## Verified baseline

On 2026-11-20, the app, camera extension, and HAL driver compiled for arm64 and x86_64 and were packaged together. Apple Silicon smoke checks passed for offline speech and timeout, rendered film and cards, and piano PCM from the compiled driver. Signed activation and enumeration by a separate camera/microphone client remain unverified.
