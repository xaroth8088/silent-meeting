# Soundtrack and provenance

[Wiki index](../AGENTS.md) · [OBS routing](../obs/AGENTS.md)

The bundled `maple-leaf-rag.mp3` uses Scott Joplin's *Maple Leaf Rag* (1899), from his 1916 piano roll. Wikimedia Commons marks the composition and piano-roll recording public domain. PlayerRoll digitized the roll to MIDI. Major Bloodnok rendered the cited version to audio. Silent Meeting adds mono EQ, wow, surface noise, and crackle. The composition and roll are public-domain material. The added sound processing is distributed with the project under MIT.

- [Wikimedia Commons source, conversion credits, and rights markings](https://commons.wikimedia.org/wiki/File:Maple_leaf_rag_-_played_by_Scott_Joplin_1916_V2.ogg)
- [Library of Congress background on the piano rolls](https://www.loc.gov/static/programs/national-recording-preservation-board/documents/RagtimeScottJoplin.pdf)
- [FFmpeg audio filters](https://ffmpeg.org/ffmpeg-filters.html)

To rebuild with curl and FFmpeg (with libmp3lame) on PATH, run `python3 assets/prepare_soundtrack.py --output /path/to/new.mp3` from the repo root. Use `--source /path/to/original.ogg` for an existing download. The script verifies the source SHA-256. The default output is the bundled path and FFmpeg refuses to overwrite it. OBS's Media Source loops the finished MP3. Keep the credited upstream version and hash in sync if the input changes.
