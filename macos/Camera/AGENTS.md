# Camera system extension

[Mac wiki](../AGENTS.md) · [Host](../App/AGENTS.md) · [Installer](../Installer/AGENTS.md)

- Publish a source for readers and a sink for the signed host. Match the sink client to the app's signing identifier and team. The camera extension captures no physical video.
- The extension reschedules the latest validated video frame on the host clock and supplies a standby card when the sender stops or stalls. On disconnect, clear the last frame and invalidate pending callbacks.
- Keep the extension executable and bundle named after its bundle identifier. The provider Mach service name and application-group entitlement must match.

Sources [Core Media I/O camera extension guide](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o) · [Apple's sink stream walkthrough](https://developer.apple.com/videos/play/wwdc2022/10022/)
