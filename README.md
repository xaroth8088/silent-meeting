# Silent Meeting

Turn your webcam into a silent film in OBS Studio. Your camera becomes black-and-white film with grain, scratches, dust, flicker, lens vignetting, and slight frame weave. A scratchy ragtime piano loop supplies the soundtrack. When you pause, locally recognized speech replaces the picture with a full-frame dialogue card, then the camera returns.

## Quick start on macOS

Use [OBS Studio](https://obsproject.com/download) and Python 3.11 or 3.12. The filter runs as a Lua extension inside OBS. Keep the repository directories together and use a dedicated OBS scene collection for the meeting.

```sh
git clone https://github.com/xaroth8088/silent-meeting.git
cd silent-meeting
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m silent_meeting
```

The first run downloads the multilingual Whisper `tiny` model. The companion prints its dialogue file path and starts listening after the model loads. Allow microphone access for the terminal or Python when macOS prompts.

1. In OBS, create a scene with a **Video Capture Device** for your webcam. Enable camera access for OBS when prompted.
2. Open **Tools → Scripts**, click **+**, and load `obs/silent-meeting.lua`. Keep the script loaded when using the scene.
3. On your camera source, open **Filters** and add **Silent Meeting** under **Effect Filters**. The default dialogue path matches the companion. Speak a sentence, pause, and look for the dialogue card in the OBS preview.
4. In **Settings → Audio**, set all **Global Audio Devices** to **Disabled** for this setup. Remove or mute any microphone, desktop, or other audio sources in the meeting scene, including any audio from the camera. Add a **Media Source** pointing to `assets/maple-leaf-rag.mp3`, check **Loop**, and name it **Silent Meeting Piano**. The piano should be the only active channel in the OBS Audio Mixer.

You can record or stream the result directly from OBS. The same scene sends the complete soundtrack to the recording or stream.

### Use it in a video call

1. Install [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) and set **OBS → Settings → Audio → Advanced → Monitoring Device** to **BlackHole 2ch**.
2. In OBS **Advanced Audio Properties**, set **Silent Meeting Piano** to **Monitor and Output**. Leave monitoring off for other sources. Keep your call's speaker output on headphones or your usual playback device.
3. Click **Start Virtual Camera** in OBS. Select **OBS Virtual Camera** as the camera and **BlackHole 2ch** as the microphone in the call. Your physical mic remains selected in the companion. If the call app suppresses the piano, enable its music or original-sound mode or reduce noise suppression.

Check the call app's audio meter before joining. It should respond to the piano and stay unchanged when you speak with the piano paused. OBS Virtual Camera carries video. BlackHole carries the separately monitored soundtrack.

### Windows and Linux

Use a native OBS build with Lua and **Text (FreeType 2)**. On Windows, use `py -3.12 -m venv .venv` and then `.venv\Scripts\python.exe` in place of `.venv/bin/python`. Install the Microsoft Visual C++ runtime if CTranslate2 requests it. On Linux, install PortAudio (for example `libportaudio2` on Debian/Ubuntu), a serif font such as DejaVu Serif, and `v4l2loopback` if your OBS installation requires it for Virtual Camera. For call audio, use a virtual audio cable on Windows or a PipeWire/PulseAudio virtual sink and its monitor on Linux. Set OBS monitoring to the playback side and the call microphone to the resulting capture side.

## Settings and privacy

- The filter offers film wear, minimum card duration, a font family, and the dialogue file location. Use a font with glyphs for your spoken language.
- The companion defaults to English and about 760 ms of quiet before ending a phrase. Try `--language auto`, `--pause-ms 1000`, or `--model base`. Use `--list-devices` and then `--device INDEX` to select a physical microphone. Run `python -m silent_meeting --help` for all options.
- Card latency is the pause plus recognition time. Long phrases are transcribed in chunks, then turned into one or more cards after the pause. Keep the piano and other callers out of the physical microphone with headphones when possible.
- Microphone PCM stays in memory. The companion writes recent dialogue to `.runtime/dialogue.tsv` and clears it on a normal exit. After a crash, stale text can remain on disk. Use a local checkout or set `--dialogue` and the filter's **Dialogue file** to the same private local path. OBS ignores stale cards. Model downloads happen separately from recognition. One companion should own each dialogue file.

## Development

```sh
python3 -m unittest discover -s tests
luac -p obs/silent-meeting.lua
```

The [agent wiki](AGENTS.md) links the OBS, speech, soundtrack, and verification notes. The project code is [MIT licensed](LICENSE). The [soundtrack notes](assets/AGENTS.md) document the separate public-domain music provenance and rebuild command.
