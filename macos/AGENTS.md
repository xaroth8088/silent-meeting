# Native Mac application

[Wiki index](../AGENTS.md) · [Host](App/AGENTS.md) · [Camera](Camera/AGENTS.md) · [Microphone](Microphone/AGENTS.md) · [Shared video](Shared/AGENTS.md) · [Installer](Installer/AGENTS.md) · [Tests](Tests/AGENTS.md)

The normal user entry point is the packaged SwiftUI app. Its physical mic and webcam inputs are separate from the two virtual devices. The app sends processed video to a signed Core Media I/O camera extension through a sink stream. The Core Audio plug-in provides predecoded piano as its only input stream. Whisper and WebRTC VAD run in the app process without a network connection. All parts compile for macOS 14 or later. The macOS implementation can ship independently of OBS.
