# OBS integration

[Wiki index](../AGENTS.md) · [Speech protocol](../silent_meeting/AGENTS.md) · [Verification](../tests/AGENTS.md)

- `silent-meeting.lua` registers a video effect filter with id `silent_meeting_film`. OBS owns the parent camera and source lifetime. FreeType draws the text after the shader replaces the frame with a bordered intertitle.
- `silent-film.effect` takes the current frame, elapsed time, wear, card state, and aspect ratio. Keep the `Draw` technique and `image` parameter expected by the libobs filter pipeline.
- The filter polls the dialogue file at most eight times a second and queues fresh, unseen pages. Keep its 20-second freshness and 12-page limits synchronized with the [writer](../silent_meeting/dialogue.py).
- A dedicated scene collection should have the piano Media Source as its only active audio. The OBS virtual camera carries the scene's video. Route the piano through OBS monitoring into a separate virtual audio cable for a call.

Sources: [OBS Lua scripting](https://docs.obsproject.com/scripting#script-sources-lua-only), [libobs source API](https://docs.obsproject.com/reference-sources), [OBS Virtual Camera](https://obsproject.com/kb/virtual-camera-guide), [BlackHole](https://github.com/ExistentialAudio/BlackHole).
