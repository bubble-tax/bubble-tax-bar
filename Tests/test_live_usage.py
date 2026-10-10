import importlib.util
import unittest
import sys
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1] / "Sources/BubbleTaxBar/Resources"))
spec = importlib.util.spec_from_file_location("live_usage", Path(__file__).parents[1] / "Sources/BubbleTaxBar/Resources/live_usage.py")
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)

class LiveUsageTests(unittest.TestCase):
    def payload(self, label="Enterprise"):
        return dict(provider="codex", source="cli", usage=dict(updatedAt="2026-10-08T10:00:00Z",
            identity=dict(loginMethod=label, accountEmail="PRIVATE@example.com", accountOrganization="PRIVATE-ORG"),
            primary=dict(usedPercent=20, windowMinutes=300, resetsAt="2026-10-08T12:00:00Z")))
    def test_metadata_does_not_export_identity_or_credentials(self):
        connection, windows = live.normalize("openai", [self.payload()])
        self.assertEqual(connection["planLabel"], "Enterprise")
        self.assertEqual(connection["status"], "connected")
        self.assertNotIn("PRIVATE", str((connection, windows)))
        self.assertEqual(windows[0]["usedPercent"], 20)
    def test_unknown_or_error_is_not_zero_usage(self):
        for value in [dict(error=dict(message="token PRIVATE")), dict(usage=None)]:
            connection, windows = live.normalize("claude", [value])
            self.assertEqual(connection["status"], "unavailable")
            self.assertEqual(windows, [])
            self.assertNotIn("PRIVATE", str(connection))
    def test_multiple_buckets_with_same_duration_stay_distinct(self):
        row = self.payload()
        row['usage']['secondary'] = dict(row['usage']['primary'], usedPercent=80)
        _, windows = live.normalize("cursor", [row])
        self.assertEqual(len(windows), 2)
        self.assertNotEqual(windows[0]['limitID'], windows[1]['limitID'])
    def test_invalid_percent_or_missing_reset_cannot_fabricate_expiry(self):
        for changes in [dict(usedPercent=-1), dict(usedPercent=101), dict(usedPercent=True), dict(resetsAt=None), dict(windowMinutes=None)]:
            row = self.payload(); row['usage']['primary'].update(changes)
            self.assertEqual(live.normalize("openai", [row])[1], [])
    def test_account_identity_is_stable_but_scoped_to_organization(self):
        row = self.payload()
        a = live.normalize("openai", [row])[0]['accountKey']
        row['usage']['identity']['accountOrganization'] = "OTHER-ORG"
        b = live.normalize("openai", [row])[0]['accountKey']
        self.assertNotEqual(a, b)
    def test_oauth_first_and_fallback_does_not_inherit_paid_plan_or_account(self):
        with patch.object(live, "fetch_source", side_effect=[
                (dict(provider="claude", status="unavailable", source="server"), []),
                (dict(provider="claude", status="connected", source="cli", planLabel="Max", accountKey="old"), [])]) as fetch:
            with patch.object(live, "cached", return_value=[dict(observedAt=1000)]):
                connection, windows = live.fetch("binary", "claude")
        self.assertEqual([call.args[2] for call in fetch.call_args_list], ["oauth", "auto"])
        self.assertEqual(connection["source"], "local statusline")
        self.assertNotIn("accountKey", connection)
        self.assertNotIn("planLabel", connection)
    def test_working_oauth_does_not_read_local_or_launch_cli(self):
        expected = live.normalize("openai", [self.payload()])
        with patch.object(live, "fetch_source", return_value=expected) as fetch:
            with patch.object(live, "cached") as cached:
                self.assertEqual(live.fetch("binary", "openai"), expected)
        fetch.assert_called_once_with("binary", "openai", "oauth")
        cached.assert_not_called()
