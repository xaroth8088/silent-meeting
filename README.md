# Silent Meeting

Silent Meeting turns your webcam into a black-and-white silent film. When you pause, your words become a dialogue card. Your meeting hears scratchy ragtime piano.

## Mac launcher

Open **Silent Meeting.app** on macOS 14 or later. The launcher uses the official OBS camera extension and BlackHole 2ch. It handles the film, local transcription, and piano routing itself.

1. Click **Install OBS** and **Install BlackHole** if the launcher shows them as missing. It downloads and checks the official installers. Follow macOS prompts to install BlackHole and restart if asked. If OBS opens as a disk image, drag it into Applications.
2. Click **Enable in OBS** if prompted. Approve OBS Virtual Camera in System Settings, then quit OBS. The launcher will use OBS's camera extension directly, so there is no OBS scene or audio mixer to configure. Leave OBS closed while Silent Meeting is running.
3. Choose your physical camera and speech microphone in Silent Meeting, click **Start**, and grant camera and microphone access. **Start on launch** reuses those choices on later launches. Use **Stop** or close the app to end capture.
4. In your meeting app, choose **OBS Virtual Camera** for video and **BlackHole 2ch** for the microphone. Leave the meeting's speaker output and macOS sound output on your headphones or speakers. Keep BlackHole dedicated to Silent Meeting during the call.

The processed preview appears in Silent Meeting. If the launcher asks you to quit OBS Studio, use **Quit OBS** in the launcher, then click **Start**. OBS Studio can take over its virtual output if it is open.

The piano is the only audio Silent Meeting writes to BlackHole. Physical microphone audio stays in memory for offline transcription. The launcher leaves the Mac's default audio devices alone.

### Build the app from source

On a Mac with Apple Command Line Tools, Python 3.11 or later, and CMake on `PATH`, run:

```sh
macos/build.sh --launcher
open ".build/macos/Silent Meeting.app"
```

The build produces a universal app for Intel and Apple Silicon with the piano track and speech model bundled. It uses local ad-hoc signing. The app uses the camera and microphone devices supplied by the upstream releases. [OBS camera approval](https://obsproject.com/kb/virtual-camera-troubleshooting) · [BlackHole](https://existential.audio/blackhole/)

## Other builds

- The [OBS script](obs/README.md) supports users who want to run the effect inside OBS on macOS, Windows, or Linux.
- The [standalone Mac installer build](macos/Installer/README.md) owns its virtual devices and requires Apple Developer ID signing and notarization.

Source code is [MIT licensed](LICENSE). See the [agent wiki](AGENTS.md) and [soundtrack credits](assets/AGENTS.md).
