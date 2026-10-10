import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "Sources/BubbleTaxBar/Resources"))
import claude_statusline as hook


class ClaudeStatuslineTests(unittest.TestCase):
    def test_capture_saves_only_real_quota_and_never_account_or_prompt(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            payload = dict(session_id="PRIVATE", cwd="PRIVATE", transcript_path="PRIVATE",
                           rate_limits=dict(five_hour=dict(used_percentage=25, resets_at=1200)))
            with patch.object(hook.time, "time", return_value=1000):
                hook.capture(home, json.dumps(payload).encode())
            _, folder = hook.paths(home)
            self.assertNotIn("PRIVATE", (folder / "quota.json").read_text())
            self.assertEqual(hook.cached(home, 1100)[0]["usedPercent"], 25)
            self.assertIsNone(hook.cached(home, 1100)[0]["accountKey"])
            self.assertEqual(hook.cached(home, 1200), [])

    def test_bridge_installed_before_rename_keeps_its_folder(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            support = home / "Library/Application Support"
            self.assertEqual(hook.paths(home)[1], support / "BubbleTaxBar/claude-statusline")
            legacy = support / "SubRIP/claude-statusline"
            legacy.mkdir(parents=True)
            (legacy / "configuration.json").write_text('{"original": null}')
            self.assertEqual(hook.paths(home)[1], legacy)

    def test_missing_invalid_and_stale_data_is_unknown(self):
        for value in [None, True, -1, 101, float("nan"), "20"]:
            self.assertEqual(hook.readings(dict(rate_limits=dict(
                five_hour=dict(used_percentage=value, resets_at=1200))), 1000), [])
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with patch.object(hook.time, "time", return_value=1000):
                hook.capture(home, b'{"rate_limits":{"seven_day":{"used_percentage":0,"resets_at":9000}}}')
            self.assertEqual(hook.cached(home, 1901), [])
            self.assertEqual(hook.cached(home, 999), [])
            with patch.object(hook.time, "time", return_value=1001):
                hook.capture(home, b'{}')
            self.assertEqual(hook.cached(home, 1002), [])

    def test_install_idempotent_and_remove_preserves_other_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            settings, folder = hook.paths(home)
            original = dict(statusLine=dict(type="command", command="printf test", padding=2), theme="dark")
            hook.atomic_json(settings, original)
            self.assertTrue(hook.configure("install", home))
            self.assertTrue(hook.configure("install", home))
            self.assertTrue(hook.configure("status", home))
            self.assertEqual(json.loads((folder / "settings-backup.json").read_text()), original)
            edited = json.loads(settings.read_text()); edited["theme"] = "light"
            hook.atomic_json(settings, edited)
            hook.configure("remove", home)
            self.assertEqual(json.loads(settings.read_text()), dict(original, theme="light"))

    def test_remove_does_not_clobber_user_replacement_and_corrupt_settings_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            settings, _ = hook.paths(home)
            hook.configure("install", home)
            edited = {"statusLine": {"type": "command", "command": "printf newer"}}
            hook.atomic_json(settings, edited)
            hook.configure("remove", home)
            self.assertEqual(json.loads(settings.read_text()), edited)
            settings.write_text("broken json")
            with self.assertRaises(ValueError):
                hook.configure("install", home)
            self.assertEqual(settings.read_text(), "broken json")

    def test_frozen_bridge_migrates_legacy_without_interpreter_and_restores_original(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            settings, folder = hook.paths(home)
            original = {"type": "command", "command": "printf original"}
            hook.atomic_json(folder / "configuration.json", {"original": original})
            hook.atomic_json(settings, {"statusLine": {"type": "command", "command": hook.shlex.join(["/missing/python3", str(folder / "bridge.py"), "capture"])}})
            binary = "/Applications/Bubble Tax.app/Contents/Helpers/BubbleTaxCollector/BubbleTaxCollector"
            self.assertFalse(hook.configure("status", home, executable=binary))
            self.assertTrue(hook.configure("install", home, executable=binary))
            self.assertTrue(hook.configure("status", home, executable=binary))
            self.assertFalse((folder / "bridge.py").exists())
            hook.configure("remove", home, executable="/moved/collector")
            self.assertEqual(json.loads(settings.read_text())["statusLine"], original)

    def test_frozen_bridge_refuses_to_overwrite_user_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            hook.configure("install", home, executable="/bundled/collector")
            settings, _ = hook.paths(home)
            changed = {"statusLine": {"type": "command", "command": "printf user"}}
            hook.atomic_json(settings, changed)
            with self.assertRaises(ValueError):
                hook.configure("install", home, executable="/updated/collector")
            hook.configure("remove", home, executable="/updated/collector")
            self.assertEqual(json.loads(settings.read_text()), changed)
