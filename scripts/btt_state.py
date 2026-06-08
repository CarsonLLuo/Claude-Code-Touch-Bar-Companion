#!/usr/bin/env python3

import argparse
import json
import os
import sys
import time


def state_path():
    base_dir = os.environ.get("CLAUDE_TOUCHBAR_DIR") or os.path.expanduser("~/.claude-touchbar")
    return os.path.join(base_dir, "state.json")


def load_state():
    try:
        with open(state_path(), "r", encoding="utf-8") as state_file:
            state = json.load(state_file)
    except (FileNotFoundError, json.JSONDecodeError):
        return None

    expires_at = int(state.get("expires_at") or 0)
    if expires_at and expires_at < int(time.time() * 1000):
        return None

    return state


def action_at(state, index):
    actions = state.get("actions") or []
    if index < 0 or index >= len(actions):
        return None
    return actions[index]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "field",
        choices=("context", "kind", "risk", "action-label", "action-id"),
    )
    parser.add_argument("index", nargs="?", type=int, default=0)
    args = parser.parse_args()

    state = load_state()

    if not state:
        if args.field == "context":
            print("CC Ready")
        else:
            print("")
        return

    if args.field == "context":
        print(state.get("context") or "Claude")
        return

    if args.field == "kind":
        print(state.get("kind") or "")
        return

    if args.field == "risk":
        print(state.get("risk") or "")
        return

    action = action_at(state, args.index)
    if not action:
        print("")
        return

    if args.field == "action-label":
        print(action.get("label") or "")
        return

    if args.field == "action-id":
        print(action.get("id") or "")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
