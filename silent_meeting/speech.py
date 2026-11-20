"""Segment microphone PCM with a voice activity detector."""

from collections import deque
from dataclasses import dataclass
from typing import Callable

RATE = 16_000
FRAME_MS = 20
FRAME_SAMPLES = RATE * FRAME_MS // 1000
FRAME_BYTES = FRAME_SAMPLES * 2
CHUNK_FRAMES = 20_000 // FRAME_MS


@dataclass(frozen=True)
class Segment:
    utterance: int
    pcm: bytes
    final: bool


class Endpointer:
    def __init__(self, pause_ms: int, is_speech: Callable[[bytes], bool]):
        self.pause_frames = (pause_ms + FRAME_MS - 1) // FRAME_MS
        self.is_speech = is_speech
        self.utterance = 0
        self.reset()

    def reset(self) -> None:
        self.pre_roll: deque[bytes] = deque(maxlen=8)
        self.votes: deque[bool] = deque(maxlen=5)
        self.buffer = bytearray()
        self.active = False
        self.quiet = 0

    def push(self, frame: bytes) -> Segment | None:
        voiced = self.is_speech(frame)
        if not self.active:
            self.pre_roll.append(frame)
            self.votes.append(voiced)
            if not voiced or sum(self.votes) < 3:
                return None
            self.utterance += 1
            self.active = True
            self.buffer.extend(b"".join(self.pre_roll))
            self.pre_roll.clear()
            self.votes.clear()
            return None

        self.buffer.extend(frame)
        self.quiet = 0 if voiced else self.quiet + 1
        if self.quiet >= self.pause_frames:
            # Keep 160 ms after the last voiced frame for the recognizer.
            trim = max(0, self.quiet - 8) * FRAME_BYTES
            segment = Segment(self.utterance, bytes(self.buffer[:len(self.buffer) - trim]), True)
            self.reset()
            return segment

        # Wait for voicing so the next chunk cannot consist solely of a trailing pause.
        if voiced and len(self.buffer) >= CHUNK_FRAMES * FRAME_BYTES:
            segment = Segment(self.utterance, bytes(self.buffer), False)
            self.buffer.clear()
            return segment
        return None
