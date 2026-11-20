# Silent Meeting

Silent Meeting turns your Mac's webcam into a black-and-white silent film. When you pause, your words become a dialogue card. The meeting hears scratchy ragtime piano through a virtual microphone. The app, virtual devices, piano track, and offline speech model are bundled in one macOS installer.

## Use Silent Meeting on Mac

**Release status.** The native build is in this repository. The package needs Apple Developer ID signing and notarization before the virtual camera can be used on a normally configured Mac. There is no signed download yet.

Once you have the signed `Silent-Meeting.pkg` for macOS 14 or later:

1. Open the package and restart when Installer requests it. It installs **Silent Meeting** and both virtual devices.
2. Open **Silent Meeting** from Applications. Click **Enable Virtual Camera** and approve the camera extension in System Settings if prompted. Choose your physical camera and microphone in Silent Meeting, then click **Start** and grant access.
3. In your meeting or recording app, choose **Silent Meeting Camera** as the camera and **Silent Meeting Piano** as the microphone. For an app that follows the system audio input, choose **Silent Meeting Piano** in **System Settings → Sound → Input**. If an app already had its device list open, reopen it to refresh the list.

Speech recognition runs offline in the app with the included Whisper model. Audio from your physical mic is used for transcription in memory. The virtual mic contains the bundled piano and crackle. It plays whenever a client opens it. When you stop the app, the virtual camera switches to a standby card.

## Build the installer

Run `macos/build.sh --unsigned` on macOS with Apple command-line developer tools, Python 3.11 or later, and CMake available. The build verifies pinned dependency downloads and produces a universal package for Apple Silicon and Intel under `.build/macos/`. The unsigned package is for build verification. For a distributable installer, see [signing and notarization](macos/Installer/README.md).

The standalone installer is for macOS. The [OBS extension](obs/README.md) remains available for OBS and other platforms. Source code is [MIT licensed](LICENSE). The [agent wiki](AGENTS.md) and [soundtrack credits](assets/AGENTS.md) are in the repo.
