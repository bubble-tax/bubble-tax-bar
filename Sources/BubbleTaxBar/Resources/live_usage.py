"""Bounded, read-only CodexBar bridge. Emit quota/plan metadata, never credentials."""
import hashlib
import json
import math
import os
import signal
import subprocess
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from claude_statusline import cached

IDS = {"openai": "codex", "claude": "claude", "cursor": "cursor",
       "copilot": "copilot", "antigravity": "antigravity"}


def epoch(value):
    if not isinstance(value, str):
        return None
    try:
        date = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return date.timestamp() if date.tzinfo else None
    except (ValueError, OverflowError):
        return None


def normalize(provider, document):
    rows = document if isinstance(document, list) else [document]
    connection = dict(provider=provider, status="unavailable", source="server")
    quotas = []
    # Fetch one ambient account. Never combine multiple organizations/accounts.
    for row in rows[:1]:
        if not isinstance(row, dict) or not isinstance(row.get("usage"), dict) or row.get("error"):
            continue
        usage = row["usage"]
        identity = usage.get("identity") or {}
        if not isinstance(identity, dict):
            identity = {}
        label = identity.get("loginMethod") or usage.get("loginMethod")
        if isinstance(label, str) and len(label) <= 160:
            connection["planLabel"] = label
        subject = identity.get("accountEmail") or usage.get("accountEmail")
        organization = identity.get("accountOrganization") or usage.get("accountOrganization") or ""
        account = hashlib.sha256((str(subject) + "|" + str(organization)).encode()).hexdigest()[:24] if subject else None
        observed = epoch(usage.get("updatedAt"))
        connection.update(status="connected", source=str(row.get("source") or "server")[:40], accountKey=account, observedAt=observed)
        labels = row.get("rateWindowLabels") or {}
        for key in ("primary", "secondary", "tertiary"):
            window = usage.get(key)
            if not isinstance(window, dict):
                continue
            used, minutes = window.get("usedPercent"), window.get("windowMinutes")
            reset = epoch(window.get("resetsAt"))
            if isinstance(used, bool) or not isinstance(used, (int, float)) or not math.isfinite(used) or not 0 <= used <= 100:
                continue
            if isinstance(minutes, bool) or not isinstance(minutes, int) or minutes <= 0 or observed is None or reset is None or reset <= observed:
                continue
            title = labels.get(key) if isinstance(labels, dict) else None
            # Keep separate model/budget windows even if their cadence matches.
            quotas.append(dict(provider=provider, limitID=IDS[provider] + ":" + key,
                               windowMinutes=minutes, resetsAt=reset, observedAt=observed,
                               usedPercent=used, accountKey=account,
                               windowLabel=title if isinstance(title, str) else None))
    return connection, quotas


def fetch_source(binary, provider, source):
    command = [binary, "usage", "--provider", IDS[provider], "--source", source,
               "--format", "json", "--no-credits"]
    process = None
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
        output, _ = process.communicate(timeout=25)
        if len(output) > 2 * 1024 * 1024:
            raise ValueError("oversized response")
        return normalize(provider, json.loads(output))
    except (OSError, ValueError, subprocess.TimeoutExpired):
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.communicate(timeout=1)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
        return dict(provider=provider, status="unavailable", source="server"), []


def fetch(binary, provider):
    sources = ["oauth", "cli"] if provider == "openai" else ["oauth", "auto"] if provider == "claude" else ["auto"]
    connection, windows = dict(provider=provider, status="unavailable", source="server"), []
    for source in sources:
        candidate, readings = fetch_source(binary, provider, source)
        if readings:
            return candidate, readings
        if candidate["status"] == "connected":
            connection = candidate
    if provider == "claude":
        fallback = cached(Path.home())
        if fallback:
            # Statusline has no verified account identity or plan. Never attach
            # it to a previous server account, or use it for paid-plan claims.
            return dict(provider=provider, status="connected", source="local statusline",
                        observedAt=max(w["observedAt"] for w in fallback)), fallback
    return connection, windows


def collect_live(binary, providers):
    connections, windows = [], []
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = pool.map(lambda provider: fetch(binary, provider), [p for p in providers if p in IDS])
        for connection, quotas in results:
            connections.append(connection)
            windows.extend(quotas)
    return connections, windows
