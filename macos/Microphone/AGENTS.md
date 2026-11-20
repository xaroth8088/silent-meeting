# Piano microphone

[Mac wiki](../AGENTS.md) · [Soundtrack provenance](../../assets/AGENTS.md) · [Tests](../Tests/AGENTS.md)

The build downloads a checksum-pinned copy of Apple's MIT-licensed NullAudio sample. `null-audio.patch` gives it distinct identifiers, publishes only the input stream, and hands input IO to `Soundtrack.c`. The sample's code and copyright stay with the driver. There is no dependency on a loopback device.

The installer converts the bundled soundtrack to mono float32 PCM at 48 kHz. The driver loads it during initialization and generates stereo samples from the Core Audio sample timeline, including when the host app is closed. Preserve the no-allocation and no-file-IO rules in the audio callback. Physical audio must never enter the driver.

Source [Apple's Audio Server Driver Plug-in sample](https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in)
