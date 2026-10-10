import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from zoneinfo import ZoneInfo

SCRIPT = Path(__file__).parents[1] / "Sources/SubRIP/Resources/collector.py"
spec = importlib.util.spec_from_file_location("collector", SCRIPT)
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)

    def write(self, name, rows):
        (self.root / name).write_text("\n".join(json.dumps(row) for row in rows) + "\n")

    def claude(self, ident="msg1", usage=None, timestamp="2026-10-01T16:00:00Z"):
        return dict(type="assistant", timestamp=timestamp,
                    message=dict(id=ident, content=[dict(text="PRIVATE PROMPT")], usage=usage or dict(input_tokens=10, output_tokens=5, cache_read_input_tokens=7, cache_creation_input_tokens=3)))

    def codex(self, total, timestamp="2026-10-01T16:00:00Z"):
        return dict(type="event_msg", timestamp=timestamp,
                    payload=dict(type="token_count", info=dict(total_token_usage=dict(total_tokens=total), last_token_usage=dict(total_tokens=100))))

    def collect(self, provider):
        return collector.collect(provider, str(self.root), ZoneInfo("Asia/Seoul"))

    def test_claude_deduplicates_blocks_and_copied_files(self):
        self.write("one.jsonl", [self.claude(), self.claude()])
        self.write("two.jsonl", [self.claude()])
        days, status = self.collect("claude")
        self.assertEqual(days, [dict(provider="claude", day="2026-10-02", tokens=25, requests=1)])
        self.assertEqual(status["status"], "ok")
        self.assertNotIn("PRIVATE", json.dumps([days, status]))

    def test_claude_streaming_updates_use_component_maximum(self):
        self.write("one.jsonl", [self.claude(usage=dict(input_tokens=10, output_tokens=2)), self.claude(usage=dict(input_tokens=10, output_tokens=5))])
        self.assertEqual(self.collect("claude")[0][0]["tokens"], 15)

    def test_codex_cumulative_counts_not_summed(self):
        self.write("one.jsonl", [self.codex(100), self.codex(100), self.codex(150, "2026-10-02T16:00:00Z")])
        days, status = self.collect("openai")
        self.assertEqual([d["tokens"] for d in days], [100, 50])
        self.assertEqual(sum(d["requests"] for d in days), 2)
        self.assertEqual(status["status"], "ok")

    def test_codex_session_id_deduplicates_resumed_copy(self):
        meta = dict(type="session_meta", payload=dict(id="s1"))
        self.write("one.jsonl", [meta, self.codex(100)])
        self.write("copy.jsonl", [meta, self.codex(100), self.codex(200, "2026-10-02T16:00:00Z")])
        self.assertEqual(sum(d["tokens"] for d in self.collect("openai")[0]), 200)

    def test_codex_input_already_includes_cache(self):
        row = self.codex(10)
        row["payload"]["info"]["total_token_usage"] = dict(input_tokens=100, output_tokens=20, cached_input_tokens=80, reasoning_output_tokens=10)
        self.write("one.jsonl", [row])
        self.assertEqual(self.collect("openai")[0][0]["tokens"], 120)

    def test_counter_reset_marks_partial_and_never_negative(self):
        self.write("one.jsonl", [self.codex(100), self.codex(20, "2026-10-02T16:00:00Z")])
        days, status = self.collect("openai")
        self.assertEqual(sum(d["tokens"] for d in days), 100)
        self.assertEqual(status["status"], "partial")

    def test_malformed_and_truncated_rows_report_partial(self):
        self.write("one.jsonl", [self.claude()])
        with (self.root / "one.jsonl").open("a") as file:
            file.write("not json\n{\"type\":")
        days, status = self.collect("claude")
        self.assertEqual(len(days), 1)
        self.assertEqual(status["malformed"], 2)
        self.assertEqual(status["status"], "partial")

    def test_unknown_usage_is_not_assumed_zero(self):
        self.write("one.jsonl", [dict(type="assistant", message=dict(id="m", usage=dict(future_counter=12)))])
        days, status = self.collect("claude")
        self.assertEqual(days, [])
        self.assertEqual(status["unsupported"], 1)
        self.assertEqual(status["status"], "partial")

    def test_empty_directory_is_not_evidence_of_nonusage(self):
        self.assertEqual(self.collect("claude")[1]["status"], "no_usage")

    def test_missing_and_unconfigured_paths_are_distinct(self):
        self.assertEqual(collector.collect("claude", None, ZoneInfo("UTC"))[1]["status"], "not_configured")
        self.assertEqual(collector.collect("claude", str(self.root / "missing"), ZoneInfo("UTC"))[1]["status"], "missing")

    def test_rate_limit_only_event_is_ignored(self):
        self.write("one.jsonl", [dict(type="event_msg", payload=dict(type="token_count", info=None))])
        self.assertEqual(self.collect("openai")[1]["status"], "no_usage")

    def test_negative_and_naive_timestamps_fail_closed(self):
        self.write("one.jsonl", [self.claude(usage=dict(input_tokens=-1)), self.claude(timestamp="2026-10-01T12:00:00")])
        days, status = self.collect("claude")
        self.assertEqual(days, [])
        self.assertEqual(status["malformed"], 2)

    def test_oversized_line_does_not_block_following_records(self):
        original = collector.MAX_LINE
        collector.MAX_LINE = 600
        self.addCleanup(setattr, collector, "MAX_LINE", original)
        (self.root / "one.jsonl").write_text('x' * 800 + '\n' + json.dumps(self.claude()) + '\n')
        days, status = self.collect("claude")
        self.assertEqual(len(days), 1)
        self.assertEqual(status["malformed"], 1)


if __name__ == "__main__":
    unittest.main()
