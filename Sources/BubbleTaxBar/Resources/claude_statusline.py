"""Optional Claude statusline bridge. Persist only sanitized quota readings."""
import argparse
import json
import math
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def paths(home):
    support = home / "Library/Application Support"
    folder, legacy = support / "BubbleTaxBar/claude-statusline", support / "SubRIP/claude-statusline"
    # A bridge installed before the SubRIP rename keeps writing to its own folder.
    if not (folder / "configuration.json").exists() and (legacy / "configuration.json").exists():
        folder = legacy
    return (home / ".claude/settings.json", folder)


def configure(action, home, script=None):
    settings, folder = paths(home)
    document = json.loads(settings.read_text()) if settings.exists() else {}
    if not isinstance(document, dict):
        raise ValueError("Settings must be an object")
    saved = folder / "configuration.json"
    command = shlex.join([sys.executable, str(folder / "bridge.py"), "capture"])
    if action == "status":
        return document.get("statusLine", {}).get("command") == command if isinstance(document.get("statusLine"), dict) else False
    if action == "install":
        if saved.exists():
            if document.get("statusLine", {}).get("command") == command:
                return True
            raise ValueError("Settings changed since installation; remove the old bridge first")
        original = document.get("statusLine")
        if original is not None and (not isinstance(original, dict) or original.get("type") != "command" or not isinstance(original.get("command"), str)):
            raise ValueError("Unsupported existing statusline")
        atomic_json(folder / "settings-backup.json", document)
        (folder / "bridge.py").write_text(Path(script or __file__).read_text())
        (folder / "bridge.py").chmod(0o600)
        atomic_json(saved, {"original": original})
        document["statusLine"] = dict(original or {}, type="command", command=command)
        try:
            atomic_json(settings, document)
        except OSError:
            saved.unlink(missing_ok=True)
            raise
        return True
    if action == "remove" and saved.exists():
        original = json.loads(saved.read_text())["original"]
        # Never overwrite a statusline changed by the user after installation.
        if isinstance(document.get("statusLine"), dict) and document["statusLine"].get("command") == command:
            if original is None:
                document.pop("statusLine", None)
            else:
                document["statusLine"] = original
            atomic_json(settings, document)
        saved.unlink()
        (folder / "quota.json").unlink(missing_ok=True)
        return False
    return False


def readings(document, now):
    limits = document.get("rate_limits") if isinstance(document, dict) else None
    if not isinstance(limits, dict):
        return []
    result = []
    for key, minutes, bucket in [("five_hour", 300, "primary"), ("seven_day", 10080, "secondary")]:
        window = limits.get(key)
        if not isinstance(window, dict):
            continue
        used, reset = window.get("used_percentage"), window.get("resets_at")
        if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in (used, reset)):
            continue
        if not 0 <= used <= 100 or not now < reset <= now + minutes * 60 + 60:
            continue
        result.append(dict(provider="claude", limitID="claude:" + bucket, windowMinutes=minutes,
                           resetsAt=reset, observedAt=now, usedPercent=used, accountKey=None))
    return result


def capture(home, raw):
    _, folder = paths(home)
    try:
        value = readings(json.loads(raw), time.time())
        # Absence is unknown. Remove the old observation instead of relabeling it fresh.
        atomic_json(folder / "quota.json", {"windows": value})
    except (ValueError, OSError, TypeError):
        pass
    try:
        original = json.loads((folder / "configuration.json").read_text()).get("original")
        if isinstance(original, dict) and original.get("command"):
            # Delegate the original user-configured display, with unchanged stdin.
            subprocess.run(original["command"], shell=True, input=raw, timeout=5,
                           stderr=subprocess.DEVNULL)
    except (ValueError, OSError, subprocess.TimeoutExpired):
        pass


def cached(home, now=None):
    now = time.time() if now is None else now
    _, folder = paths(home)
    try:
        path = folder / "quota.json"
        if path.stat().st_size > 16384:
            return []
        result = []
        for window in json.loads(path.read_text()).get("windows", []):
            if not isinstance(window, dict):
                continue
            observed = window.get("observedAt")
            if isinstance(observed, bool) or not isinstance(observed, (int, float)) or not 0 <= now - observed <= 900:
                continue
            key = {300: "five_hour", 10080: "seven_day"}.get(window.get("windowMinutes"))
            if key is None:
                continue
            sanitized = readings({"rate_limits": {key: {"used_percentage": window.get("usedPercent"), "resets_at": window.get("resetsAt")}}}, observed)
            result.extend(w for w in sanitized if w["resetsAt"] > now)
        return result
    except (OSError, ValueError, TypeError, AttributeError):
        return []


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["install", "remove", "status", "capture"])
    arguments = parser.parse_args()
    try:
        if arguments.action == "capture":
            capture(Path.home(), sys.stdin.buffer.read(2 * 1024 * 1024))
        else:
            print(json.dumps({"enabled": configure(arguments.action, Path.home())}))
    except (OSError, ValueError, TypeError, AttributeError):
        print("Could not update Claude statusline settings. Existing settings preserved.", file=sys.stderr)
        sys.exit(1)
