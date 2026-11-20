# Mac packaging

[Mac wiki](../AGENTS.md) · [Signing guide](README.md)

- `../build.sh` builds the host, camera extension, and HAL driver as one installer. Keep dependency hashes tied to their official source archives. Include notices for any bundled source, weights, and media.
- The app belongs in `/Applications`. The HAL bundle belongs in `/Library/Audio/Plug-Ins/HAL`. The installer requests a restart; it never restarts the audio daemon directly.
- The release build signs nested code first and notarizes the installer. Exercise activation and client enumeration on a normally secured Mac. Treat the unsigned build as a packaging check.
- The release build requires a Developer ID provisioning profile for the host's `com.apple.developer.system-extension.install` entitlement. The camera's team-prefixed macOS App Group needs no provisioning profile by itself. [Apple Developer Technical Support](https://developer.apple.com/forums/thread/811067) · [App Group documentation](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)

Source [Apple Notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

The `--launcher` build packages a separate ad-hoc-signed app and omits the custom virtual devices. See [launcher setup](../Launcher/AGENTS.md).
