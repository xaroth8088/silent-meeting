# Shared video format and cards

[Mac wiki](../AGENTS.md) · [Camera](../Camera/AGENTS.md) · [Host](../App/AGENTS.md)

`CameraFormat.swift` defines stable device and stream IDs and one interoperable IOSurface-backed 1280×720 BGRA format at 30 fps. Use host-clock timestamps for producer and camera samples. `Intertitle.swift` draws centered Core Text and a bordered intertitle for dialogue and standby. Keep all text within the inner border, including lines that wrap and long words.

Center each line using the midpoint of the visible glyph bounds. Wrapping can leave trailing spaces on a line, so its typographic advance can differ from the width of the drawn text. [Core Text line bounds](https://developer.apple.com/documentation/coretext/ctlineboundsoptions/useglyphpathbounds?language=objc)
