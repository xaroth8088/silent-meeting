"""Regression checks for the dialogue file contract."""

from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase
from unittest.mock import patch

from silent_meeting.dialogue import Dialogue, FRESH_SECONDS, MAX_PAGES


class DialogueTests(TestCase):
    def test_repeated_text_has_distinct_ids_and_stale_entries_are_removed(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / "runtime" / "dialogue.tsv"
            dialogue = Dialogue(path)
            with patch("silent_meeting.dialogue.time.time", return_value=1000):
                dialogue.publish("  Une\tphrase.\nTrès bien. ")
                dialogue.publish("Une phrase. Très bien.")
            first, second = [line.split("\t") for line in path.read_text().splitlines()]
            self.assertNotEqual(first[1], second[1])
            self.assertEqual(first[2], "Une phrase. Très bien.")
            self.assertEqual(first[2], second[2])

            with patch("silent_meeting.dialogue.time.time", return_value=1000 + FRESH_SECONDS):
                dialogue.publish("A fresh card.")
            self.assertEqual(len(path.read_text().splitlines()), 1)
            self.assertTrue(path.read_text().endswith("\tA fresh card.\n"))
            dialogue.clear()
            self.assertEqual(path.read_bytes(), b"")

    def test_long_dialogue_has_bounded_pages(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / "dialogue.tsv"
            Dialogue(path).publish("spoken dialogue " * 1000)
            pages = path.read_text().splitlines()
            self.assertEqual(len(pages), MAX_PAGES)
            self.assertTrue(all(len(page.split("\t")[2]) <= 132 for page in pages))
