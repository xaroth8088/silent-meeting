"""Rebuild the bundled piano loop using FFmpeg and the cited public-domain recording."""

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.request import Request, urlopen

SOURCE = (
    "https://upload.wikimedia.org/wikipedia/commons/d/db/"
    "Maple_leaf_rag_-_played_by_Scott_Joplin_1916_V2.ogg"
)
SHA256 = "61c283d86ad73ef3501baba554705793b7101ad68b8d8b011f252b14ab284646"
OUTPUT = Path(__file__).resolve().with_name("maple-leaf-rag.mp3")
FILTERS = (
    "[0:a]aformat=sample_rates=48000:channel_layouts=mono,"
    "highpass=f=135,lowpass=f=4250,equalizer=f=1650:t=q:w=1:g=1.8,"
    "vibrato=f=1.3:d=0.07,volume=0.72[piano];"
    "[1:a]bandpass=f=1850:t=o:w=2.5[hiss];"
    "[2:a]bandpass=f=1950:t=o:w=2[clicks];"
    "[piano][hiss][clicks]amix=inputs=3:duration=first:normalize=0,"
    "alimiter=limit=0.84:level=false:latency=true[mix]"
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Original Ogg file, if already downloaded")
    parser.add_argument("--output", type=Path, default=OUTPUT, help="Where to write the MP3")
    args = parser.parse_args()
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        parser.error("Install FFmpeg and add it to PATH.")

    with tempfile.TemporaryDirectory() as folder:
        source = args.source
        if source is None:
            source = Path(folder) / "piano-roll.ogg"
            request = Request(SOURCE, headers={"User-Agent": "SilentMeeting/1.0 (soundtrack builder)"})
            with urlopen(request, timeout=30) as response:
                source.write_bytes(response.read(8 * 1024 * 1024))
        if hashlib.sha256(source.read_bytes()).hexdigest() != SHA256:
            parser.error("The source recording does not match the documented SHA-256.")

        subprocess.run(
            [
                ffmpeg, "-hide_banner", "-loglevel", "error", "-n", "-i", str(source),
                "-f", "lavfi", "-i", "anoisesrc=r=48000:a=0.029:seed=74",
                "-f", "lavfi", "-i",
                "aevalsrc=if(lt(random(0)\\,0.0012)\\,0.69*(2*random(1)-1)\\,0):s=48000",
                "-filter_complex", FILTERS, "-map", "[mix]", "-map_metadata", "-1",
                "-codec:a", "libmp3lame", "-b:a", "48k",
                "-metadata", "title=Maple Leaf Rag (Silent Meeting mix)",
                "-metadata", "artist=Scott Joplin", str(args.output),
            ],
            check=True,
        )
        print(args.output)


if __name__ == "__main__":
    main()
