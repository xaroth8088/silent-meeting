# Verification

[Wiki index](../AGENTS.md) · [Speech](../silent_meeting/AGENTS.md) · [OBS](../obs/AGENTS.md)

- Run `python3 -m unittest discover -s tests` and `luac -p obs/silent-meeting.lua` from the repository root.
- Use a non-sensitive test phrase with a microphone or generated speech. Verify the camera remains visible during speech and changes to a readable intertitle after the pause. Verify that the preview returns to monochrome live video and a second identical phrase triggers a second card.
- Check playback of the bundled piano in OBS. In a call preview, test the virtual camera and the virtual audio cable. Pause the piano and speak to confirm the meeting input remains silent. Restart the piano and confirm the call input meter responds.
- Keep captures, model caches, and generated dialogue outside version control.

## Verified baseline

On 2026-11-20, Apple Silicon OBS 33.0.2 rendered a synthetic camera in monochrome, displayed a centered card from a generated phrase, and restored the camera when the card expired. WebRTC VAD and faster-whisper `tiny` produced the transcript locally. OBS loaded the looped MP3 and FFmpeg decoded the full track. Live-call audio routing and Windows/Linux execution still need manual verification.
