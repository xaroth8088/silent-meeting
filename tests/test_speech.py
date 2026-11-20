"""Regression checks for pause detection and long speech."""

from unittest import TestCase

from silent_meeting.speech import CHUNK_FRAMES, Endpointer, FRAME_BYTES

SPEECH = b"v" * FRAME_BYTES
QUIET = b"q" * FRAME_BYTES


class EndpointerTests(TestCase):
    def setUp(self):
        self.detector = Endpointer(400, lambda frame: frame == SPEECH)

    def test_short_pauses_stay_inside_one_utterance(self):
        for frame in [QUIET] * 20 + [SPEECH] * 8 + [QUIET] * 10 + [SPEECH] * 8 + [QUIET] * 19:
            self.assertIsNone(self.detector.push(frame))
        result = self.detector.push(QUIET)
        self.assertTrue(result.final)
        self.assertEqual(result.pcm, QUIET * 5 + SPEECH * 8 + QUIET * 10 + SPEECH * 8 + QUIET * 8)

    def test_long_utterance_is_chunked_and_finalized_only_on_pause(self):
        segments = [self.detector.push(SPEECH) for _ in range(CHUNK_FRAMES + 8)]
        [chunk] = [segment for segment in segments if segment is not None]
        self.assertFalse(chunk.final)
        self.assertEqual(len(chunk.pcm), CHUNK_FRAMES * FRAME_BYTES)
        for _ in range(19):
            self.assertIsNone(self.detector.push(QUIET))
        final = self.detector.push(QUIET)
        self.assertTrue(final.final)
        self.assertEqual(final.utterance, chunk.utterance)

    def test_single_voiced_frame_does_not_open_a_card(self):
        for frame in [QUIET] * 6 + [SPEECH] + [QUIET] * 30:
            self.assertIsNone(self.detector.push(frame))
