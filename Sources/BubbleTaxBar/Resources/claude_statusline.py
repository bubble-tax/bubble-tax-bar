"""Optional Claude statusline bridge. Persist only sanitized quota readings."""
import argparse
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import shlex
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


def configure(action, home, script=None, executable=None):
    settings, folder = paths(home)
    document = json.loads(settings.read_text()) if settings.exists() else {}
    if not isinstance(document, dict):
        raise ValueError("Settings must be an object")
    saved = folder / "configuration.json"
    configuration = json.loads(saved.read_text()) if saved.exists() else None
    if configuration is not None and not isinstance(configuration, dict):
        raise ValueError("Bridge configuration must be an object")
    command = shlex.join([executable, "statusline", "capture"]) if executable else shlex.join([sys.executable, str(folder / "bridge.py"), "capture"])
    statusline = document.get("statusLine")
    current = statusline.get("command") if isinstance(statusline, dict) else None
    owned = configuration is not None and current == configuration.get("command", command)
    if configuration is not None and "command" not in configuration and isinstance(current, str):
        parts = shlex.split(current)
        owned = len(parts) == 3 and parts[1:] == [str(folder / "bridge.py"), "capture"]
    if action == "status":
        return owned and current == command and configuration.get("version") == 2
    if action == "migrate":
        # Automatic upgrades touch only a bridge we still own, never a user replacement.
        if not owned:
            return False
        action = "install"
    if action == "install":
        if configuration is not None and not owned:
            # Explicit Enable replaces the current display, as the settings UI
            # states. Automatic migration returned above without touching it.
            atomic_json(folder / "configuration-before-reconnect.json", configuration)
            configuration = None
        original = configuration.get("restoreStatusLine", configuration.get("original")) if configuration is not None else statusline
        if original is not None and (not isinstance(original, dict) or original.get("type") != "command" or not isinstance(original.get("command"), str)):
            raise ValueError("Unsupported existing statusline")
        if configuration is None:
            atomic_json(folder / "settings-backup.json", document)
        elif configuration.get("version") != 2:
            atomic_json(folder / "configuration-v1-backup.json", configuration)
        bridge = folder / "bridge.py"
        if executable and bridge.exists():
            # Old tools may still call the Python bridge directly. Retire its
            # executable code, not merely the command in Claude's settings.
            backup = folder / "bridge-v1-backup.py"
            if not backup.exists():
                backup.write_bytes(bridge.read_bytes()); backup.chmod(0o600)
            bridge.write_text('"""Retired Bubble Tax bridge. Reconnect quota fallback in Bubble Tax."""\n')
            bridge.chmod(0o600)
        elif not executable:
            bridge.write_text(Path(script or __file__).read_text()); bridge.chmod(0o600)
        updated = dict(document, statusLine=dict(statusline or {}, type="command", command=command))
        # A null original stops even pre-v2 frozen collectors from delegating.
        # The restore-only value is never executed by the v2 capture path.
        atomic_json(saved, {"version": 2, "original": None, "restoreStatusLine": original, "command": command})
        try:
            atomic_json(settings, updated)
        except OSError:
            if configuration is None:
                saved.unlink(missing_ok=True)
            else:
                atomic_json(saved, configuration)
            raise
        return True
    if action == "remove" and configuration is not None:
        if owned:
            original = configuration.get("restoreStatusLine", configuration.get("original"))
            if original is None:
                document.pop("statusLine", None)
            else:
                document["statusLine"] = original
            atomic_json(settings, document)
        saved.unlink()
        (folder / "quota.json").unlink(missing_ok=True)
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


# Suppress captures invoked from a pre-v2 delegated command during migration.
NESTED = "BUBBLE_TAX_IN_STATUSLINE"


def capture(home, raw):
    if os.environ.get(NESTED) == "1":
        return
    _, folder = paths(home)
    value = []
    try:
        document = json.loads(raw)
        now = time.time()
        value = readings(document, now)
        session = document.get("session_id") if isinstance(document, dict) else None
        stream = hashlib.sha256(session.encode()).hexdigest() if isinstance(session, str) and 0 < len(session) <= 256 else None
        # Absence is unknown. Remove the old observation instead of relabeling it fresh.
        atomic_json(folder / "quota.json", {"windows": value, "streamID": stream})
        if stream and len(value) == 2:
            record_history(folder, dict(windows=value, streamID=stream), now)
    except (ValueError, OSError, TypeError):
        pass
    # No shell commands, subprocesses or shared-config delegation. The bridge
    # owns its display while connected; disconnect restores the saved command.
    labels = {300: "5h", 10080: "Wk"}
    display = " · ".join(f"{labels[w['windowMinutes']]} {100 - w['usedPercent']:g}% left" for w in value)
    print(display or "Quota unavailable")


def record_history(folder, entry, now):
    """One sanitized pair per session per five-minute bucket, even while the app is closed."""
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (folder / "history.lock").open("a") as lock:
        os.chmod(folder / "history.lock", 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = folder / "history.json"
        try:
            history = json.loads(path.read_text()) if path.stat().st_size <= 16 * 1024 * 1024 else []
        except (OSError, ValueError):
            history = []
        if not isinstance(history, list):
            history = []
        def observed(item):
            try:
                stamp = item["windows"][0]["observedAt"]
                return stamp if isinstance(stamp, (int, float)) and not isinstance(stamp, bool) and math.isfinite(stamp) else 0
            except (KeyError, IndexError, TypeError):
                return 0
        bucket = int(now // 300)
        history = [item for item in history if isinstance(item, dict) and now - 180 * 86400 <= observed(item) <= now and
                   not (item.get("streamID") == entry["streamID"] and int(observed(item) // 300) == bucket)]
        history.append(entry)
        atomic_json(path, sorted(history, key=observed)[-10000:])


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
    parser.add_argument("action", choices=["install", "remove", "status", "migrate", "capture"])
    arguments = parser.parse_args()
    try:
        if arguments.action == "capture":
            capture(Path.home(), sys.stdin.buffer.read(2 * 1024 * 1024))
        else:
            print(json.dumps({"enabled": configure(arguments.action, Path.home())}))
    except (OSError, ValueError, TypeError, AttributeError):
        print("Could not update Claude statusline settings. Existing settings preserved.", file=sys.stderr)
        sys.exit(1)
