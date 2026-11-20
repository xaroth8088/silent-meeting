# Build and sign Silent Meeting

Run the commands below from the repository root on macOS with Command Line Tools or Xcode, Python 3.11 or later, and CMake on `PATH`. If Xcode was just installed and requires first-launch setup, open Xcode to complete it. The installer includes universal app, camera extension, and HAL driver binaries. It installs under `/Applications` and `/Library/Audio/Plug-Ins/HAL`. An installer administrator approves those writes. The camera extension is activated later by the app, with macOS user approval.

## Development package

```sh
macos/build.sh --unsigned
```

The resulting `.build/macos/Silent-Meeting-0.2.0-unsigned.pkg` is for packaging checks. Its camera extension has no valid Developer ID signature. The build does not install either virtual device.

## Distribution package

1. Install a **Developer ID Application** certificate and a **Developer ID Installer** certificate from the same Apple Developer team, each with its private key, in the build account's keychain. [Apple Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
2. In **Certificates, Identifiers & Profiles**, register the explicit App ID `io.github.xaroth8088.silent-meeting` with **System Extension** enabled. Create a **Developer ID** distribution provisioning profile for that App ID using the Developer ID Application certificate. Download it and set `SILENT_APP_PROFILE` to its path. If the team uses a different app identifier, set `SILENT_BUNDLE_ID` to match. The camera extension's identifier is always the host's identifier with `.camera` appended. The stock camera extension uses a team-prefixed app group. It needs a separate profile only if the signing configuration adds an entitlement that requires one. The build accepts such a profile through `SILENT_CAMERA_PROFILE`. [Apple guidance on the System Extension entitlement](https://developer.apple.com/forums/thread/811067) · [Team-prefixed app groups](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)
3. Store the notarization credentials in Keychain as a `notarytool` profile. The command prompts for the app-specific password and checks it before saving the profile. [Apple notarization setup](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)

```sh
xcrun notarytool store-credentials silent-meeting --apple-id 'you@example.com' --team-id YOURTEAMID
```

```sh
export SILENT_TEAM_ID=YOURTEAMID
export SILENT_APP_IDENTITY='Developer ID Application: Your Name (YOURTEAMID)'
export SILENT_INSTALLER_IDENTITY='Developer ID Installer: Your Name (YOURTEAMID)'
export SILENT_APP_PROFILE='/absolute/path/to/SilentMeeting.provisionprofile'
export SILENT_NOTARY_PROFILE=silent-meeting
macos/build.sh --release
```

The release command signs the HAL bundle, camera extension, and app, signs the installer package, submits the installer for notarization, staples the ticket, and checks the result with Gatekeeper. If the selected developer tools lack `notarytool` or `stapler`, set `SILENT_NOTARY_DEVELOPER_DIR` to a configured Xcode developer directory. The final package is `.build/macos/Silent-Meeting-0.2.0.pkg`.

On a clean Mac with security enabled, install the signed package and restart. Enable the virtual camera, then use a separate app to verify both devices. Complete the [device verification steps](../Tests/AGENTS.md) before distributing a build. [Apple camera extension guide](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o) · [Apple notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Remove the devices

Quit Silent Meeting. Remove **Silent Meeting.app** from Applications and remove **SilentMeetingPiano.driver** from `/Library/Audio/Plug-Ins/HAL` as an administrator. Restart so Core Audio reloads its driver list. macOS removes the camera extension when its containing app is deleted.
