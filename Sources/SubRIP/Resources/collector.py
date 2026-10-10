#!/usr/bin/env python3
"""Read user-selected JSONL directories. Emit usage metadata, never conversation text.

Local transcript formats are undocumented/versioned; unknown formats fail closed.
Python 3.9+, standard library only. No network, credentials, or writes.
"""
import argparse
import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

MAX_LINE = 8 * 1024 * 1024


def timestamp(value, tz):
    if not isinstance(value, str):
        raise ValueError("missing timestamp")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp needs timezone")
    return parsed.astimezone(tz)


def number(value):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError("invalid token counter")
    return value


def rows(path, stats):
    try:
        with path.open("rb") as handle:
            while True:
                line = handle.readline(MAX_LINE + 1)
                if not line:
                    break
                if len(line) > MAX_LINE:
                    while line and not line.endswith(b"\n"):
                        line = handle.readline(MAX_LINE + 1)
                    stats["malformed"] += 1
                    continue
                if not line.strip():
                    continue
                try:
                    row = json.loads(line)
                    if not isinstance(row, dict):
                        raise ValueError("non-object row")
                    yield row
                except (ValueError, UnicodeError):
                    stats["malformed"] += 1
    except OSError:
        stats["unreadable"] += 1


def collect(provider, folder, tz):
    stats = dict(provider=provider, status="not_configured", files=0,
                 malformed=0, unreadable=0, unsupported=0)
    days = defaultdict(lambda: dict(tokens=0, requests=0))
    if not folder:
        return [], stats
    root = Path(folder).expanduser()
    if not root.is_dir():
        stats["status"] = "missing"
        return [], stats
    try:
        paths = sorted(p for p in root.rglob("*.jsonl") if not p.is_symlink())
    except OSError:
        stats["status"] = "unreadable"
        return [], stats
    stats["files"] = len(paths)
    messages = {}
    sessions = defaultdict(list)
    recognized = 0
    for path in paths:
        session = str(path.relative_to(root))
        for row in rows(path, stats):
            try:
                if provider == "claude":
                    if row.get("type") != "assistant":
                        continue
                    message = row.get("message", {})
                    usage = message.get("usage")
                    if not isinstance(usage, dict) or not message.get("id"):
                        stats["unsupported"] += 1
                        continue
                    if not any(k in usage for k in ("input_tokens", "output_tokens")):
                        stats["unsupported"] += 1
                        continue
                    date = timestamp(row.get("timestamp"), tz)
                    key = str(message["id"])
                    counts = tuple(number(usage.get(k, 0)) for k in (
                        "input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
                    if key in messages:
                        old_date, old_counts = messages[key]
                        messages[key] = (min(date, old_date), tuple(max(a, b) for a, b in zip(counts, old_counts)))
                    else:
                        messages[key] = (date, counts)
                    recognized += 1
                else:
                    if row.get("type") == "session_meta":
                        session = str(row.get("payload", {}).get("id") or session)
                    if row.get("type") != "event_msg" or row.get("payload", {}).get("type") != "token_count":
                        continue
                    info = row["payload"].get("info")
                    # Rate-limit-only events can have info=null and carry no usage.
                    if info is None:
                        continue
                    usage = info.get("total_token_usage")
                    if not isinstance(usage, dict):
                        stats["unsupported"] += 1
                        continue
                    total = number(usage["total_tokens"]) if "total_tokens" in usage else number(usage["input_tokens"]) + number(usage["output_tokens"])
                    date = timestamp(row.get("timestamp"), tz)
                    sessions[session].append((date, total))
                    recognized += 1
            except (ValueError, TypeError, KeyError, AttributeError, OverflowError):
                stats["malformed"] += 1
    if provider == "claude":
        for date, counts in messages.values():
            total = sum(counts)
            if total > 0:
                days[date.strftime("%Y-%m-%d")]["tokens"] += total
                days[date.strftime("%Y-%m-%d")]["requests"] += 1
    else:
        for events in sessions.values():
            previous = 0
            seen = set()
            for date, total in sorted(events):
                identity = (date, total)
                if identity in seen:
                    continue
                seen.add(identity)
                if total < previous:
                    # A reset cannot safely be attributed; surface partial coverage.
                    stats["unsupported"] += 1
                    continue
                delta = total - previous
                previous = total
                if delta > 0:
                    day = days[date.strftime("%Y-%m-%d")]
                    day["tokens"] += delta
                    day["requests"] += 1
    stats["status"] = ("partial" if any(stats[k] for k in ("malformed", "unreadable", "unsupported"))
                       else "ok" if recognized else "no_usage")
    return [dict(provider=provider, day=day, **value) for day, value in sorted(days.items())], stats


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--claude-folder")
    parser.add_argument("--codex-folder")
    parser.add_argument("--timezone", help="IANA timezone; defaults to local system timezone")
    args = parser.parse_args()
    tz = ZoneInfo(args.timezone) if args.timezone else datetime.now().astimezone().tzinfo
    result = dict(days=[], sources=[])
    for provider, folder in (("claude", args.claude_folder), ("openai", args.codex_folder)):
        days, status = collect(provider, folder, tz)
        result["days"].extend(days)
        result["sources"].append(status)
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    main()
