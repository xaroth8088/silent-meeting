# Native Mac application

[Wiki index](../AGENTS.md) · [Launcher](Launcher/AGENTS.md) · [Host](App/AGENTS.md) · [Camera](Camera/AGENTS.md) · [Microphone](Microphone/AGENTS.md) · [Shared video](Shared/AGENTS.md) · [Installer](Installer/AGENTS.md) · [Tests](Tests/AGENTS.md)

The Mac launcher uses OBS Virtual Camera and BlackHole 2ch with the shared local film and speech engine. Build it with `./macos/build.sh --launcher` from the root. The separate signed native installer retains its own camera extension and piano input. Both modes compile for macOS 14 or later.
