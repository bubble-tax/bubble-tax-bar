import json
import io
import contextlib
import subprocess
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

    def test_journal_keeps_offline_pairs_by_hashed_session_and_bounds_buckets(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            def capture(session, used, now):
                payload = dict(session_id=session, cwd="SECRET", rate_limits=dict(
                    five_hour=dict(used_percentage=used, resets_at=3000),
                    seven_day=dict(used_percentage=used / 10, resets_at=9000)))
                with patch.object(hook.time, "time", return_value=now):
                    hook.capture(home, json.dumps(payload).encode())
            capture("PRIVATE-A", 10, 1000)
            capture("PRIVATE-A", 20, 1100)
            capture("PRIVATE-A", 40, 1300)
            capture("PRIVATE-B", 50, 1310)
            _, folder = hook.paths(home)
            text = (folder / "history.json").read_text()
            self.assertNotIn("PRIVATE", text)
            self.assertNotIn("SECRET", text)
            history = json.loads(text)
            self.assertEqual(len(history), 3)
            self.assertEqual(history[0]["windows"][0]["usedPercent"], 20)
            self.assertEqual(history[0]["streamID"], history[1]["streamID"])
            self.assertNotEqual(history[1]["streamID"], history[2]["streamID"])
            self.assertEqual(len(history[0]["streamID"]), 64)
            self.assertIsNone(history[0]["windows"][0]["accountKey"])

    def test_anonymous_or_unpaired_readings_never_enter_journal(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with patch.object(hook.time, "time", return_value=1000):
                hook.capture(home, b'{"session_id":"session","rate_limits":{"five_hour":{"used_percentage":10,"resets_at":3000}}}')
                hook.capture(home, b'{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":3000},"seven_day":{"used_percentage":1,"resets_at":9000}}}')
            _, folder = hook.paths(home)
            self.assertFalse((folder / "history.json").exists())

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

    def test_explicit_enable_replaces_and_restores_current_user_display(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            hook.configure("install", home, executable="/bundled/collector")
            settings, _ = hook.paths(home)
            changed = {"statusLine": {"type": "command", "command": "printf user"}}
            hook.atomic_json(settings, changed)
            self.assertTrue(hook.configure("install", home, executable="/updated/collector"))
            self.assertTrue((hook.paths(home)[1] / "configuration-before-reconnect.json").exists())
            hook.configure("remove", home, executable="/updated/collector")
            self.assertEqual(json.loads(settings.read_text()), changed)

    def test_capture_never_executes_original_even_with_a_recursive_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            _, folder = hook.paths(home)
            marker = home / "unexpected-delegation"
            again = hook.shlex.join(["env", f"HOME={home}", sys.executable, hook.__file__, "capture"])
            hook.atomic_json(folder / "configuration.json", {"original": {
                "type": "command", "command": f"touch {hook.shlex.quote(str(marker))}; {again}"}})
            raw = b'{"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":3000},"seven_day":{"used_percentage":62,"resets_at":9000}}}'
            output = io.StringIO()
            with patch.object(hook.time, "time", return_value=1000), contextlib.redirect_stdout(output), \
                    patch("subprocess.Popen", side_effect=AssertionError("Capture must not spawn a subprocess")):
                hook.capture(home, raw)
            self.assertEqual(output.getvalue().strip(), "5h 95% left · Wk 38% left")
            self.assertFalse(marker.exists())

    def test_migration_retires_old_python_and_disables_old_frozen_delegation(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            settings, folder = hook.paths(home)
            marker = home / "old-code-ran"
            folder.mkdir(parents=True)
            bridge = folder / "bridge.py"
            old_code = f"from pathlib import Path\nPath({str(marker)!r}).touch()\n"
            bridge.write_text(old_code)
            old_command = hook.shlex.join(["/missing/python3", str(bridge), "capture"])
            original = {"type": "command", "command": "node existing-display.js"}
            hook.atomic_json(folder / "configuration.json", {"original": original})
            hook.atomic_json(settings, {"statusLine": {"type": "command", "command": old_command}, "theme": "dark"})
            self.assertTrue(hook.configure("migrate", home, executable="/new/collector"))
            configuration = json.loads((folder / "configuration.json").read_text())
            self.assertEqual(configuration["version"], 2)
            self.assertIsNone(configuration["original"])
            self.assertEqual(configuration["restoreStatusLine"], original)
            self.assertEqual((folder / "bridge-v1-backup.py").read_text(), old_code)
            subprocess.run([sys.executable, str(bridge), "capture"], input=b"{}", check=True, timeout=2)
            self.assertFalse(marker.exists())
            hook.configure("remove", home, executable="/new/collector")
            restored = json.loads(settings.read_text())
            self.assertEqual(restored["statusLine"], original)
            self.assertEqual(restored["theme"], "dark")

    def test_migration_updates_unchanged_frozen_path_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory); settings, folder = hook.paths(home)
            command = hook.shlex.join(["/same/collector", "statusline", "capture"])
            hook.atomic_json(folder / "configuration.json", {"original": None, "command": command})
            hook.atomic_json(settings, {"statusLine": {"type": "command", "command": command}})
            self.assertFalse(hook.configure("status", home, executable="/same/collector"))
            self.assertTrue(hook.configure("migrate", home, executable="/same/collector"))
            self.assertTrue(hook.configure("status", home, executable="/same/collector"))
            saved = json.loads((folder / "configuration.json").read_text())
            self.assertTrue(hook.configure("migrate", home, executable="/same/collector"))
            self.assertEqual(json.loads((folder / "configuration.json").read_text()), saved)

    def test_automatic_migration_preserves_user_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory); settings, folder = hook.paths(home)
            hook.configure("install", home, executable="/old/collector")
            replacement = {"statusLine": {"type": "command", "command": "node user-choice.js"}}
            hook.atomic_json(settings, replacement)
            saved = (folder / "configuration.json").read_bytes()
            self.assertFalse(hook.configure("migrate", home, executable="/new/collector"))
            self.assertEqual(json.loads(settings.read_text()), replacement)
            self.assertEqual((folder / "configuration.json").read_bytes(), saved)
