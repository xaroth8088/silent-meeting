"""Write short-lived dialogue snapshots for the OBS Lua filter."""

from collections import deque
from pathlib import Path
import os
import re
import tempfile
import textwrap
import time
import uuid

DEFAULT_PATH = Path(__file__).resolve().parents[1] / ".runtime" / "dialogue.tsv"
FRESH_SECONDS = 20
MAX_PAGES = 12
_GAP = r"[\s_-]+"
_CUE = "|".join((
    rf"blank{_GAP}audio", rf"no{_GAP}speech", "silence", "inaudible", "unintelligible",
    "inhal(?:e[sd]?|ing)", "exhal(?:e[sd]?|ing)", "breath(?:s|ing)?",
    "sigh(?:s|ed|ing)?", "cough(?:s|ed|ing)?", "sniff(?:s|ed|ing)?",
    "laugh(?:s|ed|ing|ter)?", "chuckl(?:e[sd]?|ing)", "applause",
    rf"clears?{_GAP}(?:their{_GAP})?throat", rf"throat{_GAP}clearing",
    rf"(?:background{_GAP})?(?:music|noise)",
))
_SOUND_MARKER = re.compile(rf"\[\s*(?:{_CUE})\s*\]|\(\s*(?:{_CUE})\s*\)", re.IGNORECASE)


class Dialogue:
    def __init__(self, path: Path):
        self.path = path
        self.session = uuid.uuid4().hex
        self.counter = 0
        self.entries: deque[tuple[int, str, str]] = deque(maxlen=MAX_PAGES)

    def _write(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=self.path.parent, delete=False
        ) as stream:
            temporary = Path(stream.name)
            try:
                for timestamp, key, text in self.entries:
                    stream.write(f"{timestamp}\t{key}\t{text}\n")
            except BaseException:
                stream.close()
                temporary.unlink(missing_ok=True)
                raise
        try:
            # Windows readers can briefly hold the old file without delete sharing.
            for attempt in range(5):
                try:
                    os.replace(temporary, self.path)
                    break
                except PermissionError:
                    if attempt == 4:
                        raise
                    time.sleep(0.03)
        finally:
            temporary.unlink(missing_ok=True)

    def publish(self, text: str) -> None:
        stripped, markers = _SOUND_MARKER.subn(" ", text)
        if markers:
            if not any(character.isalnum() for character in stripped):
                return
            stripped = re.sub(r"\s+([,.;:!?])", r"\1", stripped)
        clean = " ".join(stripped.split()).replace("\x00", "")
        now = int(time.time())
        while self.entries and now - self.entries[0][0] >= FRESH_SECONDS:
            self.entries.popleft()
        for page in textwrap.wrap(clean, width=132):
            self.counter += 1
            self.entries.append((now, f"{self.session}-{self.counter}", page))
        self._write()

    def clear(self) -> None:
        self.entries.clear()
        self._write()
