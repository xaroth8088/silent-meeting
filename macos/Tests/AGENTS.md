# Native device verification

[Mac wiki](../AGENTS.md) · [Installer](../Installer/README.md)

- The packaging script can run the native smoke tests without installing a device. Use `SILENT_RUN_TESTS=1` and set `SILENT_TEST_PCM` to a short 16 kHz mono s16le recording of “The meeting is now in session” with at least a second of trailing silence. Use public or locally generated test audio.
- `Smoke.swift` feeds the real WebRTC VAD and Whisper model and checks pause finalization, sound cue removal, and card timing. Its pixel checks include centering both lines of a wrapped card and grain changes across successive frames of the same title. `DriverSmoke.c` uses the compiled HAL driver's interface to check device properties and receive actual piano PCM in process.
- Inject short, breath-like noise after the generated phrase and check that the first finalized chunk arrives within 800 ms and transcribes the whole phrase. A separate check resumes speech after 200 ms and expects one utterance.
- On a normally secured test Mac, install the signed package, restart, enable the virtual camera, and select both devices in a separate camera/microphone app. Confirm the preview and remote camera show the same card and its expiration. Check that the virtual input contains piano while speech produces cards. Check that no physical audio reaches the virtual mic. Stop capture and confirm the camera goes to standby. Verify device selection when multiple clients use the devices.

## Verified baseline

On 2026-11-20, the app, camera extension, and HAL driver compiled for arm64 and x86_64 and were packaged together. Apple Silicon smoke checks passed for offline speech and timeout, rendered film and cards, and piano PCM from the compiled driver. Signed activation and enumeration by a separate camera/microphone client remain unverified.

## OBS and BlackHole launcher

- Build with `macos/build.sh --launcher` and the same speech test environment. `LauncherSmoke.swift` verifies frame adaptation to the OBS BGRA format, looping mono-to-stereo PCM for BlackHole, the missing-device guard, and download checksum checking.
- Use a Mac with the official OBS and BlackHole builds to complete first-run setup, then quit OBS. Start the launcher and select **OBS Virtual Camera** and **BlackHole 2ch** in a second app. Confirm the video changes from film to a dialogue card after a phrase and that the mic contains only piano. Verify that stopping the launcher clears both outputs and reopening it restores the connection. An output device containing BlackHole should block playback until normal speakers or headphones are selected.

On 2026-11-20, Apple Silicon launcher smoke tests passed with generated speech and a synthetic video frame. Verified the OBS disk image checksum and app signature, and the BlackHole package checksum and notarization. Actual virtual-device activation and call audio still require the first-run approvals and a live client check.

The 0.3.1 launcher also passed a live test with OBS Studio closed. The physical camera drove the rendered launcher preview, and an independent Core Media I/O reader received 28 of 28 sampled frames as 1920×1080 monochrome video from OBS Virtual Camera. The test retained only aggregate statistics.
