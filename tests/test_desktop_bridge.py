import contextlib
import importlib.util
import io
import os
import time
import unittest
from pathlib import Path


BRIDGE_PATH = Path(__file__).parents[1] / "Sources/DevarDesktop/Resources/desktop_bridge.py"
FIXTURE_PATH = Path(__file__).parent / "fixtures/tiny-bible.json"
os.environ["DEVAR_BIBLE_PATH"] = str(FIXTURE_PATH)
spec = importlib.util.spec_from_file_location("desktop_bridge", BRIDGE_PATH)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class VerseSuggestionTests(unittest.TestCase):
    def test_whisper_window_merge_drops_repeated_overlap(self):
        result = bridge._merge_transcript_overlap(
            "The preacher said John three sixteen and then",
            "and then reminded us God so loved the world",
        )
        self.assertEqual(result, "The preacher said John three sixteen and then reminded us God so loved the world")

    def test_quote_ranks_exact_kjv_passage_first(self):
        bridge.load_bible("KJV")
        bridge._last_query = ""
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            bridge.suggest(
                "God showed deep love for the world and gave hope to everyone",
                force=True,
            )

        import json

        event = json.loads(output.getvalue())
        self.assertEqual(event["type"], "suggestions")
        self.assertEqual(event["suggestions"][0]["reference"], "John 3:16")
        self.assertEqual(event["suggestions"][0]["translation"], "KJV")

    @unittest.skipUnless(
        importlib.util.find_spec("devar_engine.references"),
        "The released PyPI engine does not include live reference tracking yet.",
    )
    def test_spoken_reference_bypasses_context_refresh_delay(self):
        from devar_engine.references import SpokenReferenceTracker

        bridge.load_bible("KJV")
        bridge._reference_tracker = SpokenReferenceTracker()
        bridge._last_query = ""
        bridge._last_suggested_at = time.monotonic()
        bridge._refresh_seconds = 3.0
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            bridge.suggest("Matthew chapter 13 verse 11", force=False)

        import json

        event = json.loads(output.getvalue())
        self.assertEqual(event["type"], "suggestions")
        self.assertEqual(event["suggestions"][0]["reference"], "Matthew 13:11")
        self.assertEqual(event["suggestions"][0]["translation"], "KJV")

    @unittest.skipUnless(
        importlib.util.find_spec("devar_engine.references"),
        "The released PyPI engine does not include live reference tracking yet.",
    )
    def test_compound_spoken_reference_is_promoted_immediately(self):
        from devar_engine.references import SpokenReferenceTracker

        bridge.load_bible("KJV")
        bridge._reference_tracker = SpokenReferenceTracker()
        bridge._last_direct_references = set()
        bridge._preferred_direct_reference = None
        bridge._last_query = ""
        bridge._last_suggested_at = time.monotonic()
        bridge._refresh_seconds = 3.0
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            bridge.suggest("Job thirty eight thirty three", force=False)

        import json

        event = json.loads(output.getvalue())
        self.assertEqual(event["suggestions"][0]["reference"], "Job 38:33")

    @unittest.skipUnless(
        importlib.util.find_spec("devar_engine.references"),
        "The released PyPI engine does not include live reference tracking yet.",
    )
    def test_new_reference_moves_ahead_of_older_reference_in_rolling_context(self):
        from devar_engine.references import SpokenReferenceTracker

        bridge.load_bible("KJV")
        bridge._reference_tracker = SpokenReferenceTracker()
        bridge._last_direct_references = set()
        bridge._preferred_direct_reference = None
        bridge._last_query = ""
        bridge._last_suggested_at = time.monotonic()
        bridge._refresh_seconds = 3.0

        import json

        first_output = io.StringIO()
        with contextlib.redirect_stdout(first_output):
            bridge.suggest("Matthew 13:11", force=False)
        self.assertEqual(json.loads(first_output.getvalue())["suggestions"][0]["reference"], "Matthew 13:11")

        second_output = io.StringIO()
        with contextlib.redirect_stdout(second_output):
            bridge.suggest("Matthew 13:11 and now Job 38:33", force=False)
        event = json.loads(second_output.getvalue())
        self.assertEqual(event["suggestions"][0]["reference"], "Job 38:33")

    @unittest.skipUnless(
        importlib.util.find_spec("devar_engine.references"),
        "The released PyPI engine does not include live reference tracking yet.",
    )
    def test_fresh_quote_can_replace_an_older_spoken_reference(self):
        from devar_engine.references import SpokenReferenceTracker

        bridge.load_bible("KJV")
        bridge._reference_tracker = SpokenReferenceTracker()
        bridge._last_direct_references = set()
        bridge._preferred_direct_reference = None
        bridge._last_query = ""
        bridge._last_suggested_at = 0.0

        import json

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            bridge.suggest(
                "Matthew 13:11",
                force=False,
                reference_text="Matthew 13:11",
            )
        exact_event = json.loads(output.getvalue())
        self.assertEqual(exact_event["suggestions"][0]["reference"], "Matthew 13:11")

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            bridge.suggest(
                "Matthew 13:11. What do you know of the appointed order of the heavens? Can you govern their influence on the earth?",
                force=True,
                reference_text="What do you know of the appointed order of the heavens? Can you govern their influence on the earth?",
            )
        contextual_event = json.loads(output.getvalue())
        self.assertEqual(contextual_event["suggestions"][0]["reference"], "Job 38:33")


if __name__ == "__main__":
    unittest.main()
