"""Run the Silent Meeting microphone companion."""

import argparse
import logging
from pathlib import Path
import queue
import sys
import threading

from .dialogue import DEFAULT_PATH, Dialogue
from .speech import Endpointer, FRAME_SAMPLES, RATE, Segment

LOG = logging.getLogger("silent-meeting")


def recognize(model, language, jobs, dialogue, failed):
    import numpy as np

    current = None
    parts = []
    try:
        while (job := jobs.get()) is not None:
            if current != job.utterance:
                current = job.utterance
                parts.clear()
            if job.pcm:
                samples = np.frombuffer(job.pcm, dtype="<i2").astype("float32") / 32768.0
                segments, _ = model.transcribe(
                    samples, language=language, beam_size=1, condition_on_previous_text=False
                )
                parts.extend(segment.text.strip() for segment in segments)
            if job.final:
                text = " ".join(part for part in parts if part)
                if text:
                    dialogue.publish(text)
                parts.clear()
    except Exception as error:
        failed.put(error)


def capture(args, sounddevice):
    from faster_whisper import WhisperModel
    import webrtcvad

    dialogue = Dialogue(args.dialogue.expanduser().resolve())
    dialogue.clear()
    try:
        LOG.info("Loading speech model %s. The first run may download model weights.", args.model)
        model = WhisperModel(args.model, device="cpu", compute_type="default", cpu_threads=args.threads)
        vad = webrtcvad.Vad(args.vad)
        endpointer = Endpointer(args.pause_ms, lambda frame: vad.is_speech(frame, RATE))
        jobs: queue.Queue[Segment | None] = queue.Queue(maxsize=6)
        failed: queue.SimpleQueue[Exception] = queue.SimpleQueue()
        worker = threading.Thread(
            target=recognize, args=(model, args.language, jobs, dialogue, failed)
        )
        worker.start()
        try:
            with sounddevice.RawInputStream(
                samplerate=RATE, blocksize=FRAME_SAMPLES, device=args.device,
                channels=1, dtype="int16"
            ) as stream:
                LOG.info("Listening for speech. OBS dialogue file: %s", dialogue.path)
                while failed.empty():
                    frame, overflow = stream.read(FRAME_SAMPLES)
                    if overflow:
                        LOG.warning("Microphone overflow. Dropping the interrupted phrase.")
                        endpointer.reset()
                    segment = endpointer.push(bytes(frame))
                    if segment is not None:
                        try:
                            jobs.put_nowait(segment)
                        except queue.Full:
                            LOG.warning("Speech recognition is behind. Dropping the interrupted phrase.")
                            endpointer.reset()
        finally:
            # Discard queued speech on exit and join the active inference before clearing the file.
            while True:
                try:
                    jobs.get_nowait()
                except queue.Empty:
                    break
            jobs.put_nowait(None)
            worker.join()
        if not failed.empty():
            raise failed.get()
    finally:
        dialogue.clear()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list-devices", action="store_true", help="List audio devices and exit")
    parser.add_argument("--device", help="Microphone name or numeric index from --list-devices")
    parser.add_argument("--model", default="tiny", help="faster-whisper model name or local model path")
    parser.add_argument("--language", default="en", help="Spoken language code, or auto (default: en)")
    parser.add_argument("--pause-ms", type=int, default=760, help="End-of-phrase silence in milliseconds")
    parser.add_argument("--vad", type=int, choices=range(4), default=2, help="VAD aggressiveness")
    parser.add_argument("--threads", type=int, default=4, help="CPU threads for speech recognition")
    parser.add_argument("--dialogue", type=Path, default=DEFAULT_PATH, help="Path shared with the OBS filter")
    args = parser.parse_args()
    if not 200 <= args.pause_ms <= 3000 or args.threads < 1:
        parser.error("--pause-ms must be 200–3000 and --threads must be positive")
    if args.device and args.device.isdecimal():
        args.device = int(args.device)
    if args.language == "auto":
        args.language = None

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        import sounddevice

        if args.list_devices:
            print(sounddevice.query_devices())
        else:
            capture(args, sounddevice)
    except KeyboardInterrupt:
        return 0
    except Exception as error:
        LOG.error("%s", error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
