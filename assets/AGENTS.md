# Soundtrack and provenance

[Wiki index](../AGENTS.md) · [OBS routing](../obs/AGENTS.md)

The bundled `maple-leaf-rag.mp3` uses Scott Joplin's *Maple Leaf Rag* (1899), from his 1916 piano roll. Wikimedia Commons marks the composition and piano-roll recording public domain. PlayerRoll digitized the roll to MIDI. Major Bloodnok rendered the cited version to audio. Silent Meeting adds mono EQ, wow, surface noise, and crackle. The composition and roll are public-domain material. The added sound processing is distributed with the project under MIT.

- [Wikimedia Commons source, conversion credits, and rights markings](https://commons.wikimedia.org/wiki/File:Maple_leaf_rag_-_played_by_Scott_Joplin_1916_V2.ogg)
- [Library of Congress background on the piano rolls](https://www.loc.gov/static/programs/national-recording-preservation-board/documents/RagtimeScottJoplin.pdf)
- [FFmpeg audio filters](https://ffmpeg.org/ffmpeg-filters.html)

The launcher adds two 48-second opening excerpts. The pieces are in the public domain and the modern source recordings are dedicated to the public domain under CC0 1.0. Apply the same vintage processing to all three tracks and keep the perceived level similar when switching.

| Loop | Composition | Source recording |
| --- | --- | --- |
| `the-entertainer.mp3` | Scott Joplin, *The Entertainer* (1902) | James Brigham performance (2018). [Wikimedia Commons](https://commons.wikimedia.org/w/index.php?title=File:%22The_Entertainer%22_(1902),_by_Scott_Joplin.mp3&oldid=920325953) |
| `gymnopedie-no-1.mp3` | Erik Satie, *Gymnopédie No. 1* (1888) | Teknopazzo recording. [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Gymnopedie_No._1..ogg) |

To rebuild with curl and FFmpeg (with libmp3lame) on PATH, run `python3 assets/prepare_soundtrack.py --track the-entertainer --output /path/to/new.mp3` from the repo root. The track IDs match the file names without `.mp3` and default to `maple-leaf-rag`. Pass `--source /path/to/original` to reuse a download. The script verifies the source SHA-256 and FFmpeg refuses to overwrite an existing file. Keep the credited recording and hash in sync if the input changes.
