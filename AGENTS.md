# Silent Meeting wiki

Start here, then read the page in the directory you are changing. The source, the linked upstream references, and verified behavior are the evidence for these summaries.

## Index

| Page | Topic |
| --- | --- |
| [Native Mac](macos/AGENTS.md) | Standalone host, virtual camera, piano microphone, and signed packaging |
| [OBS](obs/AGENTS.md) | Lua filter registration, shader, intertitle rendering, stream and call routing |
| [Speech](silent_meeting/AGENTS.md) | End-of-utterance behavior, local inference, and the dialogue file contract |
| [Assets](assets/AGENTS.md) | Piano roll provenance and the FFmpeg rebuild |
| [Tests](tests/AGENTS.md) | Automated and manual verification |

## Maintain the wiki

Read the relevant implementation and upstream sources. Update the nearest page with the resulting durable decisions, invariants, and links in the same change. Update this index when pages move or are added. Append a dated entry when an architectural decision, source, or verification baseline changes. Check code references, links, platform claims, and protocol constants during maintenance. Keep user recordings and transcripts out of the wiki.

## Change log

- 2026-11-20 · Architecture · Adopted OBS Lua for video and a companion for local speech. Reused OBS Media Source and platform loopbacks for audio delivery. Applied the linked-page, source, index, and log pattern from [Andrej Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).
- 2026-11-20 · Verification · Confirmed the Apple Silicon speech and OBS rendering path with generated input. See [verification](tests/AGENTS.md).
- 2026-11-20 · Architecture · Added the standalone Mac app, Core Media I/O camera extension, and Core Audio piano microphone. Retained OBS as a separate fallback. See the [Mac wiki](macos/AGENTS.md).
- 2026-11-20 · Signing · Confirmed that the host requires a Developer ID provisioning profile to install the camera extension. See [Mac packaging](macos/Installer/AGENTS.md).
