# Mac launcher with OBS and BlackHole

[Mac wiki](../AGENTS.md) · [App pipeline](../App/AGENTS.md) · [Verification](../Tests/AGENTS.md)

- `Setup.swift` detects and retrieves the official OBS app and BlackHole 2ch package. Keep checksums paired with the upstream version and architecture. Let Installer and System Settings own installation privileges and camera extension approval. Preserve existing OBS bundles and profiles.
- `LauncherApp.swift` owns the UI and remembers the first successful start. Capture begins on a later launch only if the user has left automatic start enabled and both devices are ready. Abort when a device disappears or normal speaker output would feed BlackHole.
- `BlackHolePiano.swift` writes the bundled soundtrack to the exact BlackHole 2ch hardware UID with Audio Queue Services. Physical mic PCM never enters this queue. A missing device or rejected route is an error. Keep the Mac's default input and output unchanged.
- Load the three 48 kHz mono piano loops into memory before starting the audio queue. The callback checks for a new track without blocking and crossfades over 120 ms. A sentiment score of +0.8 or higher selects *The Entertainer*. A score of −0.9 or lower selects *Mysterioso—Burglar Music No. 1*. Scores between them select *Maple Leaf Rag*. Each choice carries through until the next scored card.
- The host sends video straight to OBS Virtual Camera's CMIO sink. Keep OBS closed while the launcher owns that sink. OBS's sink UUID and format behavior are upstream implementation details. Verify compatibility when changing the pinned build.

Sources [OBS camera extension](https://github.com/obsproject/obs-studio/tree/33.0.2/plugins/mac-virtualcam/src/camera-extension) · [BlackHole distribution](https://github.com/ExistentialAudio/BlackHole) · [Apple Audio Queue properties](https://developer.apple.com/documentation/audiotoolbox/audioqueuepropertyid)
