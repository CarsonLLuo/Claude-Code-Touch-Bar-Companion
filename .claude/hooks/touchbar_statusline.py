#!/usr/bin/env python3
"""Claude Code status line for the Touch Bar companion.

Reads the status line JSON from stdin, records plan usage for the Touch Bar app,
and prints a short usage line for the terminal.

Writes (under ~/.claude-touchbar/ or $CLAUDE_TOUCHBAR_DIR):
  usage.json            latest snapshot, replaced atomically on every run
  usage-history.jsonl   one line per change in 5h / 7d usage, kept for 8 days
"""

import json
import os
import sys
import tempfile
import time

HISTORY_KEEP_MS = 8 * 24 * 3600 * 1000
HISTORY_PRUNE_BYTES = 512 * 1024


def base_dir():
    return os.environ.get("CLAUDE_TOUCHBAR_DIR") or os.path.expanduser("~/.claude-touchbar")


def atomic_write(path, text):
    directory = os.path.dirname(path)
    fd, tmp_path = tempfile.mkstemp(prefix="tmp-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp:
            tmp.write(text)
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def rate_window(data, name):
    window = (data.get("rate_limits") or {}).get(name) or {}
    used = window.get("used_percentage")
    resets_at = window.get("resets_at")
    if used is None or resets_at is None:
        return None
    return {"used_percentage": float(used), "resets_at": int(resets_at)}


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def prune_history(path, now_ms):
    with open(path, "r", encoding="utf-8") as handle:
        lines = handle.readlines()
    kept = []
    for line in lines:
        try:
            if json.loads(line).get("at", 0) >= now_ms - HISTORY_KEEP_MS:
                kept.append(line)
        except json.JSONDecodeError:
            continue
    atomic_write(path, "".join(kept))


def record(data, now_ms):
    directory = base_dir()
    os.makedirs(directory, exist_ok=True)
    usage_path = os.path.join(directory, "usage.json")
    history_path = os.path.join(directory, "usage-history.jsonl")

    usage = {
        "updated_at": now_ms,
        "session_id": data.get("session_id"),
        "five_hour": rate_window(data, "five_hour"),
        "seven_day": rate_window(data, "seven_day"),
        "context_used_percentage": (data.get("context_window") or {}).get("used_percentage"),
        "cost_usd": (data.get("cost") or {}).get("total_cost_usd"),
    }
    previous = load_json(usage_path)
    windows = (usage["five_hour"], usage["seven_day"])
    if not any(windows):
        # No rate limit data yet (new session before its first response, or an API key
        # session): keep the last known account-level numbers and their timestamp.
        usage["five_hour"] = previous.get("five_hour")
        usage["seven_day"] = previous.get("seven_day")
        usage["updated_at"] = previous.get("updated_at", now_ms)
    atomic_write(usage_path, json.dumps(usage, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    if any(windows) and windows != (previous.get("five_hour"), previous.get("seven_day")):
        row = {"at": now_ms, "five_hour": usage["five_hour"], "seven_day": usage["seven_day"]}
        with open(history_path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, separators=(",", ":")) + "\n")
        if os.path.getsize(history_path) > HISTORY_PRUNE_BYTES:
            prune_history(history_path, now_ms)

    return usage


def status_text(usage):
    parts = []
    for label, key in (("5h", "five_hour"), ("7d", "seven_day")):
        window = usage[key]
        if window:
            parts.append(f"{label} {100 - window['used_percentage']:.0f}% left")
    context = usage["context_used_percentage"]
    if context is not None:
        parts.append(f"ctx {context:.0f}%")
    return " · ".join(parts) or "Claude Code"


def main():
    try:
        data = json.loads(sys.stdin.read())
        print(status_text(record(data, int(time.time() * 1000))))
    except Exception:
        print("Claude Code")


if __name__ == "__main__":
    main()
