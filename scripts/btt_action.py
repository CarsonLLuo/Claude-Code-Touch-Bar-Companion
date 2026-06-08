#!/usr/bin/env python3

import argparse
import json
import os
import sys
import tempfile
import time


BLOCKED_DIRECT_ACTIONS = {
    "allow",
    "allow_once",
    "allow_session_edits",
    "allow_session_read",
    "always_allow",
    "run",
}


def base_dir():
    return os.environ.get("CLAUDE_TOUCHBAR_DIR") or os.path.expanduser("~/.claude-touchbar")


def load_state():
    path = os.path.join(base_dir(), "state.json")
    try:
        with open(path, "r", encoding="utf-8") as state_file:
            return json.load(state_file)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def action_at(state, index):
    actions = state.get("actions") or []
    if index < 0 or index >= len(actions):
        return None
    return actions[index]


def atomic_write(path, text):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix="tmp-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp:
            tmp.write(text)
            tmp.flush()
            os.fsync(tmp.fileno())
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def log_action(row):
    os.makedirs(base_dir(), exist_ok=True)
    path = os.path.join(base_dir(), "actions.jsonl")
    with open(path, "a", encoding="utf-8") as log_file:
        log_file.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")


def write_response(state, action, now_ms):
    request_id = state.get("request_id")
    if not request_id:
        return False

    response = {
        "request_id": request_id,
        "session_id": state.get("session_id") or "unknown",
        "clicked_at": now_ms,
        "kind": state.get("kind") or "unknown",
        "risk": state.get("risk") or "unknown",
        "action_id": action.get("id") or "",
        "action_label": action.get("label") or "",
    }
    if action.get("updated_permissions"):
        response["updated_permissions"] = action["updated_permissions"]

    path = os.path.join(base_dir(), "responses", f"{request_id}.json")
    atomic_write(
        path,
        json.dumps(response, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    )
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("index", type=int)
    args = parser.parse_args()

    state = load_state()
    now_ms = int(time.time() * 1000)
    if not state:
        return 1

    expires_at = int(state.get("expires_at") or 0)
    if expires_at and expires_at < now_ms:
        return 1

    action = action_at(state, args.index)
    if not action:
        return 1

    action_id = action.get("id") or ""
    risk = state.get("risk") or "unknown"
    if risk in ("high", "unknown") and action_id in BLOCKED_DIRECT_ACTIONS:
        return 1

    response_written = False
    if state.get("kind") == "PermissionRequest":
        response_written = write_response(state, action, now_ms)

    log_action(
        {
            "clicked_at": now_ms,
            "response_written": response_written,
            "session_id": state.get("session_id") or "unknown",
            "kind": state.get("kind") or "unknown",
            "context": state.get("context") or "",
            "risk": risk,
            "action": action,
        }
    )

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(1)
