#!/usr/bin/env python3
"""Read user-selected JSONL directories. Emit usage metadata, never conversation text.

Local transcript formats are undocumented/versioned; unknown formats fail closed.
Python 3.9+, standard library only. No network, credentials, or writes.
"""
import argparse
import json
import math
import hashlib
import re
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


def quota_readings(row, tz):
    payload = row.get("payload")
    if not isinstance(payload, dict):
        return []
    limits = payload.get("rate_limits")
    if not isinstance(limits, dict):
        return []
    try:
        observed = timestamp(row.get("timestamp"), tz).timestamp()
    except (ValueError, TypeError, OverflowError):
        return []
    result = []
    for key in ("primary", "secondary"):
        window = limits.get(key)
        if not isinstance(window, dict):
            continue
        used, minutes, reset = (window.get(k) for k in ("used_percent", "window_minutes", "resets_at"))
        values = (used, minutes, reset)
        if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in values):
            continue
        if not 0 <= used <= 100 or minutes <= 0 or int(minutes) != minutes or reset <= observed:
            continue
        result.append(dict(provider="openai", limitID=str(limits.get("limit_id") or "codex"),
                           windowMinutes=int(minutes), resetsAt=reset, observedAt=observed, usedPercent=used))
    return result


def compact_quotas(readings):
    # Account-wide snapshots repeat across conversations. Never sum them.
    buckets = defaultdict(list)
    for reading in readings:
        buckets[(reading["provider"], reading.get("accountKey"), reading["limitID"], reading["windowMinutes"])].append(reading)
    result = []
    for values in buckets.values():
        cluster = []
        for reading in sorted(values, key=lambda r: r["resetsAt"]):
            # CLI reset timestamps drift by seconds within the same period.
            # Anchor the tolerance to the first timestamp, not a chained gap.
            if cluster and reading["resetsAt"] - cluster[0]["resetsAt"] > 60:
                result.append(max(cluster, key=lambda r: (r["observedAt"], r["usedPercent"])))
                cluster = []
            cluster.append(reading)
        if cluster:
            result.append(max(cluster, key=lambda r: (r["observedAt"], r["usedPercent"])))
    return sorted(result, key=lambda r: (r["resetsAt"], r["windowMinutes"], r["limitID"]))


def safe_model(value):
    if isinstance(value, str) and len(value) <= 100 and re.fullmatch(r"(?:claude-|gpt-|o[1-9](?:-|$))[A-Za-z0-9_.:-]*", value):
        return value
    return None


def model_event(provider, key, date, model, counts, total=None, breakdown=True):
    return dict(id=hashlib.sha256((provider + "|" + key).encode()).hexdigest()[:24],
                provider=provider, timestamp=date.timestamp(), model=model,
                input=counts[0], output=counts[1], cacheRead=counts[2], cacheWrite=counts[3],
                tokens=sum(counts) if total is None else total, breakdownKnown=breakdown)


def collect(provider, folder, tz, quotas=None, model_usage=None):
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
    model_conflicts = set()
    sessions = defaultdict(list)
    recognized = 0
    for path in paths:
        session = str(path.relative_to(root))
        current_model = None
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
                        old_date, old_counts, old_model, old_latest = messages[key]
                        new_model = safe_model(message.get("model"))
                        model = new_model or old_model
                        if old_model and new_model and old_model != new_model:
                            model_conflicts.add(key)
                        if key in model_conflicts:
                            model = None
                        messages[key] = (min(date, old_date), tuple(max(a, b) for a, b in zip(counts, old_counts)), model, max(date, old_latest))
                    else:
                        messages[key] = (date, counts, safe_model(message.get("model")), date)
                    recognized += 1
                else:
                    if row.get("type") == "turn_context":
                        current_model = safe_model(row.get("payload", {}).get("model"))
                    if row.get("type") == "session_meta":
                        session = str(row.get("payload", {}).get("id") or session)
                    if row.get("type") != "event_msg" or row.get("payload", {}).get("type") != "token_count":
                        continue
                    if quotas is not None:
                        quotas.extend(quota_readings(row, tz))
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
                    # Codex input includes cached input; reasoning output is already
                    # part of output. Keep counter components to derive deltas.
                    raw_counts = tuple(number(usage.get(k, 0)) for k in (
                        "input_tokens", "output_tokens", "cached_input_tokens", "cache_write_input_tokens"))
                    last = info.get("last_token_usage") or {}
                    last_total = last.get("total_tokens") if isinstance(last, dict) else None
                    if isinstance(last_total, bool) or not isinstance(last_total, int):
                        last_total = None
                    sessions[session].append((date, total, current_model, raw_counts, last_total))
                    recognized += 1
            except (ValueError, TypeError, KeyError, AttributeError, OverflowError):
                stats["malformed"] += 1
    if provider == "claude":
        for key, (date, counts, model, latest) in messages.items():
            total = sum(counts)
            if total > 0:
                days[date.strftime("%Y-%m-%d")]["tokens"] += total
                days[date.strftime("%Y-%m-%d")]["requests"] += 1
                if model_usage is not None:
                    # Claude input excludes cache reads/writes.
                    normalized = (counts[0], counts[1], counts[3], counts[2])
                    model_usage.append(model_event(provider, key, latest, model, normalized))
    else:
        for session_id, events in sessions.items():
            previous = 0
            previous_counts = (0, 0, 0, 0)
            seen = set()
            for date, total, model, counts, last_total in sorted(events, key=lambda e: (e[0], e[1])):
                identity = (date, total)
                if identity in seen:
                    continue
                seen.add(identity)
                if total < previous:
                    # A reset cannot safely be attributed; surface partial coverage.
                    stats["unsupported"] += 1
                    continue
                delta = total - previous
                old_counts = previous_counts
                previous = total
                previous_counts = counts
                if delta > 0:
                    day = days[date.strftime("%Y-%m-%d")]
                    day["tokens"] += delta
                    day["requests"] += 1
                    if model_usage is not None:
                        components = tuple(max(0, a-b) for a,b in zip(counts, old_counts))
                        # Do not double-count cached or reasoning tokens.
                        normalized = (max(0, components[0]-components[2]-components[3]), components[1], components[2], components[3])
                        key = session_id + "|" + date.isoformat() + "|" + str(total)
                        # A cumulative jump can cover several turns/models. Only
                        # attach a model when this increment matches the last turn.
                        event_model = model if last_total == delta else None
                        breakdown = sum(normalized) == delta and all(a >= b for a,b in zip(counts, old_counts))
                        model_usage.append(model_event(provider, key, date, event_model, normalized, delta, breakdown))
    stats["status"] = ("partial" if any(stats[k] for k in ("malformed", "unreadable", "unsupported"))
                       else "ok" if recognized else "no_usage")
    return [dict(provider=provider, day=day, **value) for day, value in sorted(days.items())], stats


def collect_pi(folder, tz):
    """Local activity only: token totals never establish billing or quota left."""
    stats = dict(status="not_configured", files=0, malformed=0, unreadable=0, unsupported=0)
    if not folder:
        return dict(days=[], **stats)
    root = Path(folder).expanduser()
    if not root.is_dir():
        stats["status"] = "missing"
        return dict(days=[], **stats)
    try:
        paths = sorted(p for p in root.rglob("*.jsonl") if not p.is_symlink())
    except OSError:
        stats["status"] = "unreadable"
        return dict(days=[], **stats)
    stats["files"] = len(paths)
    known = {"openai-codex", "github-copilot", "anthropic", "openai", "google", "google-vertex",
             "amazon-bedrock", "azure", "openrouter", "kimi-coding", "zai", "zai-coding-cn",
             "minimax", "minimax-cn", "qwen-token-plan", "qwen-token-plan-cn", "radius"}
    messages = {}
    now = datetime.now(tz)
    for path in paths:
        valid_session = False
        for row in rows(path, stats):
            if row.get("type") == "session":
                valid_session = not isinstance(row.get("version"), bool) and row.get("version") in (1, 2, 3)
                if not valid_session:
                    stats["unsupported"] += 1
                continue
            if not valid_session:
                continue
            if row.get("type") == "message":
                message = row.get("message")
                if not isinstance(message, dict) or message.get("role") != "assistant":
                    continue
            elif row.get("type") == "usage":
                message = row
            else:
                if isinstance(row.get("usage"), dict):
                    stats["unsupported"] += 1  # summary lacks reliable provider attribution
                continue
            try:
                date = timestamp(row.get("timestamp"), tz)
                usage = message.get("usage")
                if date > now or not isinstance(usage, dict) or not row.get("id"):
                    raise ValueError("invalid usage metadata")
                total = number(usage["totalTokens"]) if "totalTokens" in usage else sum(
                    number(usage.get(k, 0)) for k in ("input", "output", "cacheRead", "cacheWrite"))
                if not any(k in usage for k in ("totalTokens", "input", "output")):
                    raise ValueError("missing counters")
                provider = message.get("provider")
                provider = provider if isinstance(provider, str) and provider in known else "other"
                # Forks/copies retain entry IDs. Prefer the upstream response ID if supplied.
                identity = str(message.get("responseId") or row["id"])
                key = (provider, identity, str(message.get("timestamp") or row.get("timestamp")))
                old = messages.get(key)
                messages[key] = (date, max(total, old[1] if old else 0))
            except (ValueError, TypeError, KeyError, OverflowError):
                stats["malformed"] += 1
    days = defaultdict(lambda: dict(tokens=0, requests=0))
    for key, (date, tokens) in messages.items():
        if tokens:
            day = days[(key[0], date.strftime("%Y-%m-%d"))]
            day["tokens"] += tokens; day["requests"] += 1
    stats["status"] = "partial" if any(stats[k] for k in ("malformed", "unreadable", "unsupported")) else "ok" if messages else "no_usage"
    return dict(days=[dict(providerID=p, day=d, **v) for (p, d), v in sorted(days.items())], **stats)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--claude-folder")
    parser.add_argument("--codex-folder")
    parser.add_argument("--pi-folder")
    parser.add_argument("--live-binary")
    parser.add_argument("--providers", default="openai,claude")
    parser.add_argument("--timezone", help="IANA timezone; defaults to local system timezone")
    args = parser.parse_args()
    tz = ZoneInfo(args.timezone) if args.timezone else datetime.now().astimezone().tzinfo
    result = dict(days=[], sources=[], quotaWindows=[], modelUsage=[], modelUsageTruncated=[])
    if args.pi_folder:
        result["piUsage"] = collect_pi(args.pi_folder, tz)
    for provider, folder in (("claude", args.claude_folder), ("openai", args.codex_folder)):
        model_usage = []
        days, status = collect(provider, folder, tz, result["quotaWindows"], model_usage)
        if len(model_usage) > 2000:
            result["modelUsageTruncated"].append(provider)
        result["modelUsage"].extend(sorted(model_usage, key=lambda e: e["timestamp"])[-2000:])
        result["days"].extend(days)
        result["sources"].append(status)
    if args.live_binary:
        from live_usage import collect_live
        connections, windows = collect_live(args.live_binary, args.providers.split(","))
        result["connections"] = connections
        connected = {c["provider"] for c in connections if c["status"] == "connected"}
        # Local transcript account ownership isn't verified. Don't merge it into
        # a server-identified account or a managed workspace's quota history.
        result["quotaWindows"] = [q for q in result["quotaWindows"] if q["provider"] not in connected] + windows
    result["quotaWindows"] = compact_quotas(result["quotaWindows"])
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    main()
