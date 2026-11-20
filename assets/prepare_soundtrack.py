"""Rebuild the bundled piano loops using FFmpeg and public-domain recordings."""

import argparse
from dataclasses import dataclass
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile

COMMONS = "https://upload.wikimedia.org/wikipedia/commons/"


@dataclass(frozen=True)
class Track:
    source: str
    sha256: str
    title: str
    artist: str
    gain: float = 0.72
    seconds: int | None = None


TRACKS = {
    "maple-leaf-rag": Track(
        "d/db/Maple_leaf_rag_-_played_by_Scott_Joplin_1916_V2.ogg",
        "61c283d86ad73ef3501baba554705793b7101ad68b8d8b011f252b14ab284646",
        "Maple Leaf Rag", "Scott Joplin",
    ),
    "the-entertainer": Track(
        "b/bd/%22The_Entertainer%22_%281902%29%2C_by_Scott_Joplin.mp3",
        "d666009b399f632b22da8783afd1545d1372fce2b0d782c5f4b8e882c875f146",
        "The Entertainer", "Scott Joplin", gain=0.41, seconds=48,
    ),
    "gymnopedie-no-1": Track(
        "b/b7/Gymnopedie_No._1..ogg",
        "13e4e03797169392166b9f11d9bf9c421c022b48ad87d9b10bd441ce068502da",
        "Gymnopédie No. 1", "Erik Satie", gain=0.82, seconds=48,
    ),
}

FILTERS = (
    "[0:a]aformat=sample_rates=48000:channel_layouts=mono,"
    "highpass=f=135,lowpass=f=4250,equalizer=f=1650:t=q:w=1:g=1.8,"
    "vibrato=f=1.3:d=0.07,volume={gain}{excerpt}[piano];"
    "[1:a]bandpass=f=1850:t=o:w=2.5[hiss];"
    "[2:a]bandpass=f=1950:t=o:w=2[clicks];"
    "[piano][hiss][clicks]amix=inputs=3:duration=first:normalize=0,"
    "alimiter=limit=0.84:level=false:latency=true[mix]"
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--track", choices=TRACKS, default="maple-leaf-rag")
    parser.add_argument("--source", type=Path, help="Original recording, if already downloaded")
    parser.add_argument("--output", type=Path, help="Where to write the MP3")
    args = parser.parse_args()
    track = TRACKS[args.track]
    output = args.output or Path(__file__).resolve().with_name(f"{args.track}.mp3")
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        parser.error("Install FFmpeg and add it to PATH.")

    with tempfile.TemporaryDirectory() as folder:
        source = args.source
        if source is None:
            curl = shutil.which("curl")
            if not curl:
                parser.error("Install curl or pass the original recording with --source.")
            source = Path(folder) / "piano-source"
            subprocess.run(
                [curl, "-fsSL", "--max-time", "30", "--max-filesize", "8388608",
                 "--user-agent", "SilentMeeting/1.0 (soundtrack builder)",
                 "-o", str(source), COMMONS + track.source],
                check=True,
            )
        if hashlib.sha256(source.read_bytes()).hexdigest() != track.sha256:
            parser.error("The source recording does not match the documented SHA-256.")

        excerpt = ""
        if track.seconds is not None:
            excerpt = (f",atrim=duration={track.seconds},afade=t=in:d=0.012,"
                       f"afade=t=out:st={track.seconds - 0.25}:d=0.25")

        subprocess.run(
            [
                ffmpeg, "-hide_banner", "-loglevel", "error", "-n", "-i", str(source),
                "-f", "lavfi", "-i", "anoisesrc=r=48000:a=0.029:seed=74",
                "-f", "lavfi", "-i",
                "aevalsrc=if(lt(random(0)\\,0.0012)\\,0.69*(2*random(1)-1)\\,0):s=48000",
                "-filter_complex", FILTERS.format(gain=track.gain, excerpt=excerpt),
                "-map", "[mix]", "-map_metadata", "-1",
                "-codec:a", "libmp3lame", "-b:a", "48k",
                "-metadata", f"title={track.title} (Silent Meeting mix)",
                "-metadata", f"artist={track.artist}", str(output),
            ],
            check=True,
        )
        print(output)


if __name__ == "__main__":
    main()
