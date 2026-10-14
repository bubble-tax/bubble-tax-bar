import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from zoneinfo import ZoneInfo

SCRIPT = Path(__file__).parents[1] / "Sources/BubbleTaxBar/Resources/collector.py"
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

    def pi_message(self, ident="pi1", provider="openai-codex", usage=None):
        return dict(type="message", id=ident, timestamp="2026-10-01T16:00:00Z", message=dict(
            role="assistant", provider=provider, timestamp=1790870400000, content=[dict(text="PRIVATE PI TEXT")],
            usage=usage or dict(input=10, output=5, cacheRead=7, cacheWrite=3, totalTokens=25)))

    def test_pi_deduplicates_forks_and_keeps_routes_separate(self):
        header = dict(type="session", version=3, id="session")
        rows = [header, self.pi_message(), self.pi_message("api", "openai"), self.pi_message("claude", "anthropic")]
        self.write("pi.jsonl", rows)
        self.write("pi-fork.jsonl", rows)
        result = collector.collect_pi(str(self.root), ZoneInfo("Asia/Seoul"))
        self.assertEqual(result["status"], "ok")
        self.assertEqual(sum(d["tokens"] for d in result["days"]), 75)
        self.assertEqual({d["providerID"] for d in result["days"]}, {"openai-codex", "openai", "anthropic"})
        self.assertTrue(all(d["day"] == "2026-10-02" for d in result["days"]))
        self.assertNotIn("PRIVATE", json.dumps(result))
        self.assertNotIn("quota", json.dumps(result))

    def test_pi_rejects_invalid_usage_and_handles_versions_and_extra_usage(self):
        header = dict(type="session", version=3, id="session")
        self.write("pi.jsonl", [header, self.pi_message(usage=dict(totalTokens=-1)),
            dict(type="usage", id="cache", timestamp="2026-10-01T16:00:00Z", provider="github-copilot", usage=dict(totalTokens=12)),
            dict(type="compaction", id="summary", timestamp="2026-10-01T16:00:00Z", usage=dict(totalTokens=8)),
            self.pi_message("custom", "PRIVATE PROVIDER")])
        self.write("new-version.jsonl", [dict(type="session", version=99), self.pi_message("ignored")])
        result = collector.collect_pi(str(self.root), ZoneInfo("Asia/Seoul"))
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["malformed"], 1)
        self.assertEqual(result["unsupported"], 2)
        self.assertEqual(sum(d["tokens"] for d in result["days"]), 37)
        self.assertNotIn("PRIVATE", json.dumps(result))
        self.assertEqual(collector.collect_pi(None, ZoneInfo("Asia/Seoul"))["status"], "not_configured")
        self.assertEqual(collector.collect_pi(str(self.root / "missing"), ZoneInfo("Asia/Seoul"))["status"], "missing")

    def test_claude_model_metadata_streams_and_copies_do_not_double_count(self):
        first = self.claude(usage=dict(input_tokens=10, output_tokens=2, cache_read_input_tokens=30, cache_creation_input_tokens=5))
        first["message"]["model"] = "claude-opus-4-6"
        final = self.claude(usage=dict(input_tokens=10, output_tokens=6, cache_read_input_tokens=30, cache_creation_input_tokens=5))
        final["message"]["model"] = "claude-opus-4-6"
        other = self.claude(ident="sonnet", usage=dict(input_tokens=20, output_tokens=5))
        other["message"]["model"] = "claude-sonnet-4-6"
        self.write("one.jsonl", [first, final, other])
        self.write("copy.jsonl", [final])
        events = []
        collector.collect("claude", str(self.root), ZoneInfo("UTC"), model_usage=events)
        self.assertEqual(len(events), 2)
        opus = next(e for e in events if e["model"] == "claude-opus-4-6")
        self.assertEqual((opus["tokens"], opus["input"], opus["output"], opus["cacheRead"], opus["cacheWrite"]), (51, 10, 6, 30, 5))
        self.assertNotIn("PRIVATE", json.dumps(events))
        self.assertNotIn("msg1", json.dumps(events))

    def test_codex_model_switches_use_deltas_without_double_counting_cache(self):
        def usage(total, input_tokens, output, cache, last):
            row = self.codex(total)
            row["payload"]["info"] = dict(total_token_usage=dict(total_tokens=total, input_tokens=input_tokens, output_tokens=output, cached_input_tokens=cache, reasoning_output_tokens=output), last_token_usage=dict(total_tokens=last))
            return row
        a = usage(100, 80, 20, 50, 100)
        b = usage(160, 120, 40, 70, 60); b["timestamp"] = "2026-10-01T16:05:00Z"
        meta = dict(type="session_meta", payload=dict(id="session"))
        context = lambda m: dict(type="turn_context", payload=dict(model=m, summary="PRIVATE"))
        records = [meta, context("gpt-5.4"), a, context("gpt-5.4-mini"), b]
        self.write("one.jsonl", records); self.write("copy.jsonl", records)
        events = []
        collector.collect("openai", str(self.root), ZoneInfo("UTC"), model_usage=events)
        self.assertEqual([(e["model"], e["tokens"]) for e in events], [("gpt-5.4", 100), ("gpt-5.4-mini", 60)])
        self.assertEqual((events[0]["input"], events[0]["output"], events[0]["cacheRead"]), (30, 20, 50))
        self.assertEqual((events[1]["input"], events[1]["output"], events[1]["cacheRead"]), (20, 20, 20))
        self.assertNotIn("PRIVATE", json.dumps(events))

    def test_missing_models_and_multi_turn_jumps_remain_unknown(self):
        a = self.claude(); a["message"]["model"] = "PRIVATE PROMPT"
        self.write("claude.jsonl", [a])
        events = []
        collector.collect("claude", str(self.root), ZoneInfo("UTC"), model_usage=events)
        self.assertIsNone(events[0]["model"])
        self.write("codex.jsonl", [dict(type="turn_context", payload=dict(model="gpt-5.4")), self.codex(500)])
        events = []
        collector.collect("openai", str(self.root), ZoneInfo("UTC"), model_usage=events)
        self.assertIsNone(events[0]["model"])
        self.assertFalse(events[0]["breakdownKnown"])

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

    def quota(self, used=20, reset=1790868000, timestamp="2026-10-01T12:00:00Z"):
        return dict(type="event_msg", timestamp=timestamp, payload=dict(type="token_count", info=None,
            rate_limits=dict(limit_id="codex", primary=dict(used_percent=used, window_minutes=300, resets_at=reset))))

    def test_rate_limit_only_events_preserve_quota_without_faking_tokens(self):
        self.write("one.jsonl", [self.quota()])
        quotas = []
        days, status = collector.collect("openai", str(self.root), ZoneInfo("UTC"), quotas)
        self.assertEqual(days, [])
        self.assertEqual(len(quotas), 1)
        self.assertEqual(quotas[0]["usedPercent"], 20)
        self.assertNotIn("plan_type", quotas[0])

    def test_quota_deduplicates_sessions_and_reset_timestamp_jitter(self):
        quotas = [r for row in [self.quota(), self.quota(used=40, reset=1790868008, timestamp="2026-10-01T12:10:00Z"),
                                self.quota(), self.quota(used=5, reset=1790886000, timestamp="2026-10-01T17:00:00Z")]
                  for r in collector.quota_readings(row, ZoneInfo("UTC"))]
        result = collector.compact_quotas(quotas)
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0]["usedPercent"], 40)

    def test_invalid_quota_is_not_reported_as_unused(self):
        for value in (-1, 101, True, float("nan"), "5"):
            self.assertEqual(collector.quota_readings(self.quota(used=value), ZoneInfo("UTC")), [])
        self.assertEqual(collector.quota_readings(self.quota(reset=1), ZoneInfo("UTC")), [])

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
