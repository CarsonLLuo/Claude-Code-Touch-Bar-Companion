#!/usr/bin/env python3

import json
import os
import re
import shlex
import sys
import tempfile
import time
import uuid


HIGH_RISK_PATTERN = re.compile(
    r"sudo|rm +-.*[rR]|chmod -R|chown -R|curl +.*\| *sh|wget +.*\| *sh|~/.ssh|/Library|/System"
)
DEFAULT_EXPIRES_MS = 30000
DEFAULT_PERMISSION_WAIT_MS = 20000
# The question waits in a background (asyncRewake) hook, so it can stay up for a while.
DEFAULT_QUESTION_WAIT_MS = 5 * 60 * 1000
# Claude desktop's end-of-turn "next step" box (question + reply buttons).
QUESTION_TOOL = "mcp__ccd_turn__wrap_up"
QUESTION_MAX_AGE_MS = 15 * 60 * 1000
MAX_QUESTION_CHOICES = 2
POLL_INTERVAL_SECONDS = 0.2
MAX_TARGET_CHARS = 34


def atomic_write(path, text):
    directory = os.path.dirname(path)
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


def permission_wait_ms():
    value = os.environ.get("CLAUDE_TOUCHBAR_PERMISSION_TIMEOUT_MS")
    if not value:
        return DEFAULT_PERMISSION_WAIT_MS
    try:
        return max(0, int(value))
    except ValueError:
        return DEFAULT_PERMISSION_WAIT_MS


def question_wait_ms():
    value = os.environ.get("CLAUDE_TOUCHBAR_QUESTION_TIMEOUT_MS")
    try:
        return max(0, int(value)) if value else DEFAULT_QUESTION_WAIT_MS
    except ValueError:
        return DEFAULT_QUESTION_WAIT_MS


def command_text(event):
    tool_input = event.get("tool_input") or {}
    return (
        tool_input.get("command")
        or tool_input.get("pattern")
        or tool_input.get("file_path")
        or tool_input.get("path")
        or ""
    )


def shorten_middle(value, limit):
    if len(value) <= limit:
        return value

    keep = max(4, (limit - 1) // 2)
    return f"{value[:keep]}…{value[-keep:]}"


def shorten_path(path_text):
    if len(path_text) <= MAX_TARGET_CHARS:
        return path_text

    parts = path_text.split("/")
    basename = parts[-1] if parts else path_text
    if len(parts) > 1:
        candidate = f"{parts[0]}/…/{basename}"
        if len(candidate) <= MAX_TARGET_CHARS:
            return candidate

        basename_limit = max(8, MAX_TARGET_CHARS - len(parts[0]) - 3)
        return f"{parts[0]}/…/{shorten_middle(basename, basename_limit)}"

    return shorten_middle(path_text, MAX_TARGET_CHARS)


def display_target(event):
    tool_input = event.get("tool_input") or {}
    value = str(command_text(event))

    path_value = tool_input.get("file_path") or tool_input.get("path")
    cwd = event.get("cwd")
    if path_value:
        path_text = str(path_value)
        if cwd:
            try:
                path_text = os.path.relpath(path_text, cwd)
            except ValueError:
                pass
        if path_text.startswith("../"):
            path_text = os.path.basename(path_text)
        return shorten_path(path_text)

    return shorten_middle(value, MAX_TARGET_CHARS)


def bash_command(event):
    tool_input = event.get("tool_input") or {}
    return str(tool_input.get("command") or "")


def bash_parts(event):
    try:
        return shlex.split(bash_command(event))
    except ValueError:
        return []


def path_inside_cwd(path_text, cwd):
    if not cwd:
        return False

    full_path = path_text
    if not os.path.isabs(full_path):
        full_path = os.path.join(cwd, full_path)

    try:
        common = os.path.commonpath([os.path.realpath(cwd), os.path.realpath(full_path)])
    except ValueError:
        return False

    return common == os.path.realpath(cwd)


def display_path(path_text, cwd):
    shown = path_text
    if cwd:
        try:
            shown = os.path.relpath(path_text, cwd) if os.path.isabs(path_text) else path_text
        except ValueError:
            shown = os.path.basename(path_text)

    if shown.startswith("../"):
        shown = os.path.basename(shown)

    return shorten_path(shown)


def rm_command_info(event):
    parts = bash_parts(event)

    if not parts or os.path.basename(parts[0]) != "rm":
        return None

    targets = []
    recursive = False
    after_double_dash = False

    for part in parts[1:]:
        if not after_double_dash and part == "--":
            after_double_dash = True
            continue

        if not after_double_dash and part.startswith("-"):
            if "r" in part or "R" in part:
                recursive = True
            continue

        targets.append(part)

    return {
        "recursive": recursive,
        "targets": targets,
    }


def rm_risk(event):
    info = rm_command_info(event)
    if not info:
        return None

    targets = info["targets"]
    cwd = event.get("cwd")

    if info["recursive"] or not targets:
        return "high"

    for target in targets:
        if any(char in target for char in "*?["):
            return "high"
        if not path_inside_cwd(target, cwd):
            return "high"
        target_path = target if os.path.isabs(target) else os.path.join(cwd or "", target)
        if os.path.isdir(target_path):
            return "high"

    return "medium"


def first_non_option(parts):
    after_double_dash = False
    for part in parts:
        if not after_double_dash and part == "--":
            after_double_dash = True
            continue
        if not after_double_dash and part.startswith("-"):
            continue
        return part
    return ""


def script_target(parts, cwd):
    for part in parts:
        if part.startswith("-"):
            continue
        if part == "-m":
            return ""
        if part.endswith((".py", ".js", ".ts", ".sh", ".rb", ".php")):
            return display_path(part, cwd)
    return ""


def bash_summary(event):
    parts = bash_parts(event)
    if not parts:
        return shorten_middle(bash_command(event), MAX_TARGET_CHARS)

    command = os.path.basename(parts[0])
    args = parts[1:]
    cwd = event.get("cwd")

    if command in ("python", "python3"):
        script = script_target(args, cwd)
        if script:
            return f"Python {script}"
        if "-m" in args:
            index = args.index("-m")
            if index + 1 < len(args):
                return f"Python -m {shorten_middle(args[index + 1], 18)}"
        return "Python"

    if command in ("node", "bun", "deno"):
        script = script_target(args, cwd)
        if script:
            return f"{command} {script}"
        return command

    if command in ("npm", "pnpm", "yarn"):
        first = first_non_option(args)
        if first:
            second = first_non_option(args[args.index(first) + 1 :]) if first in ("run", "exec") else ""
            suffix = f" {first}"
            if second:
                suffix += f" {second}"
            return shorten_middle(f"{command}{suffix}", MAX_TARGET_CHARS)
        return command

    if command in ("pytest", "ruff", "mypy", "tsc", "make"):
        first = first_non_option(args)
        suffix = f" {shorten_middle(first, 18)}" if first else ""
        return f"{command}{suffix}"

    if command in ("cat", "sed", "awk", "grep", "rg", "find", "ls"):
        first = first_non_option(args)
        suffix = f" {display_path(first, cwd)}" if first else ""
        return shorten_middle(f"{command}{suffix}", MAX_TARGET_CHARS)

    return shorten_middle(command, 22)


def git_action_summary(event):
    """`Commit & push`, `Commit` or `Push` when the command (possibly chained with &&) runs those."""
    parts = bash_parts(event)
    subcommands = set()
    for index, part in enumerate(parts):
        if os.path.basename(part) == "git":
            subcommand = first_non_option(parts[index + 1 :])
            if subcommand:
                subcommands.add(subcommand)
    if {"commit", "push"} <= subcommands:
        return "Commit & push"
    if "commit" in subcommands:
        return "Commit"
    if "push" in subcommands:
        return "Push"
    return None


def bash_context_text(event, prefix):
    git_summary = git_action_summary(event)
    if git_summary:
        return git_summary

    rm_info = rm_command_info(event)
    if rm_info and rm_info["targets"]:
        cwd = event.get("cwd")
        target = display_path(rm_info["targets"][0], cwd)
        suffix = " +" if len(rm_info["targets"]) > 1 else ""
        return f"Delete {target}{suffix}"

    return f"{prefix} {bash_summary(event)}"


def write_context_text(event, target):
    tool_input = event.get("tool_input") or {}
    path = tool_input.get("file_path")
    if path and not os.path.exists(str(path)):
        return f"Create {target}"
    return f"Write {target}"


def context_text(event):
    event_name = event.get("hook_event_name") or "unknown"
    tool_name = event.get("tool_name") or "tool"
    target = display_target(event)

    if event_name == "PermissionRequest":
        if tool_name == "Bash":
            return bash_context_text(event, "Run")
        if tool_name == "Read":
            return f"Read {target}"
        if tool_name == "Write":
            return write_context_text(event, target)
        if tool_name in ("Edit", "MultiEdit"):
            return f"Edit {target}"
        return f"{tool_name}?"

    if event_name == "PreToolUse":
        if tool_name == "Bash":
            return bash_context_text(event, "Running")
        return f"Using {tool_name}"

    if event_name == "PostToolUse":
        return f"Done {tool_name}"

    if event_name == "PostToolUseFailure":
        return f"Failed {tool_name}"

    if event_name == "Notification":
        return str(event.get("message") or event.get("notification_type") or "Claude notification")

    if event_name == "Stop":
        return "Claude done"

    if event_name == "UserPromptSubmit":
        return "Claude working"

    return event_name


def risk_level(event):
    event_name = event.get("hook_event_name") or "unknown"
    tool_name = event.get("tool_name") or ""
    tool_input = event.get("tool_input") or {}
    command = str(tool_input.get("command") or "")

    rm_level = rm_risk(event)
    if rm_level:
        return rm_level

    if tool_name == "Bash" and HIGH_RISK_PATTERN.search(command):
        return "high"

    if event_name == "PermissionRequest" and tool_name in ("Write", "Edit", "MultiEdit"):
        return "medium"

    if event_name == "PermissionRequest":
        return "low"

    return "unknown"


def session_edit_suggestion(event):
    suggestions = event.get("permission_suggestions") or []
    for suggestion in suggestions:
        if not isinstance(suggestion, dict):
            continue
        if (
            suggestion.get("type") == "setMode"
            and suggestion.get("mode") == "acceptEdits"
            and suggestion.get("destination") == "session"
        ):
            return suggestion
    return None


def read_session_permission(event):
    tool_input = event.get("tool_input") or {}
    target = tool_input.get("file_path") or tool_input.get("path")
    cwd = event.get("cwd")
    if not target:
        target = cwd
    if not target:
        return None

    path_text = str(target)
    if not os.path.isabs(path_text) and cwd:
        path_text = os.path.join(cwd, path_text)

    directory = os.path.normpath(path_text)
    if not os.path.isdir(directory):
        directory = os.path.dirname(directory)
    if not directory or directory == os.path.sep:
        return None

    posix_directory = directory.replace(os.path.sep, "/")
    rule_content = f"/{posix_directory}/**" if os.path.isabs(directory) else f"{posix_directory}/**"
    return {
        "type": "addRules",
        "rules": [{"toolName": "Read", "ruleContent": rule_content}],
        "behavior": "allow",
        "destination": "session",
    }


def actions_for_state(event, risk):
    event_name = event.get("hook_event_name") or "unknown"
    tool_name = event.get("tool_name") or ""

    if event_name == "PermissionRequest" and risk in ("low", "medium"):
        if tool_name == "Read":
            read_permission = read_session_permission(event)
            if read_permission:
                return [
                    {"id": "allow", "label": "Yes"},
                    {
                        "id": "allow_session_read",
                        "label": "Yes all session",
                        "updated_permissions": [read_permission],
                    },
                    {"id": "deny", 
                    "label": "No"},
                ]

        edit_session_suggestion = session_edit_suggestion(event)
        if edit_session_suggestion:
            return [
                {"id": "allow", "label": "Yes"},
                {
                    "id": "allow_session_edits",
                    "label": "All edits",
                    "updated_permissions": [edit_session_suggestion],
                },
                {"id": "deny", "label": "No"},
            ]

        return [
            {"id": "allow", "label": "Yes"},
            {"id": "deny", "label": "No"},
            {"id": "screen", "label": "Review"},
        ]

    if event_name == "PermissionRequest":
        return [
            {"id": "review", "label": "Review on screen"},
            {"id": "deny", "label": "No"},
        ]

    return []


def sanitized_event(event):
    clean = dict(event)

    if "last_assistant_message" in clean:
        clean["last_assistant_message"] = "[redacted]"

    if "prompt" in clean:
        clean["prompt"] = "[redacted]"

    tool_input = clean.get("tool_input")
    if isinstance(tool_input, dict) and "content" in tool_input:
        clean_input = dict(tool_input)
        content = clean_input.get("content") or ""
        clean_input["content"] = f"[redacted {len(content)} chars]"
        clean["tool_input"] = clean_input

    tool_response = clean.get("tool_response")
    if isinstance(tool_response, dict):
        clean_response = dict(tool_response)
        file_response = clean_response.get("file")
        if isinstance(file_response, dict) and "content" in file_response:
            clean_file = dict(file_response)
            content = clean_file.get("content") or ""
            clean_file["content"] = f"[redacted {len(content)} chars]"
            clean_response["file"] = clean_file
        clean["tool_response"] = clean_response

    return clean


def response_path(base_dir, request_id):
    return os.path.join(base_dir, "responses", f"{request_id}.json")


def decision_for_response(response):
    action_id = response.get("action_id") or ""

    if action_id in ("allow", "allow_session_edits", "allow_session_read"):
        decision = {
            "behavior": "allow",
        }
        updated_permissions = response.get("updated_permissions")
        if updated_permissions:
            decision["updatedPermissions"] = updated_permissions

        return {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": decision,
            },
        }

    if action_id == "deny":
        return {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "deny",
                    "message": "Denied from Touch Bar",
                },
            },
        }

    return None


def mark_decided(state_path, state, action_id):
    updated = dict(state)
    if action_id in ("allow", "allow_session_edits", "allow_session_read"):
        updated["context"] = "Touch Bar allowed"
    elif action_id == "deny":
        updated["context"] = "Touch Bar denied"
    elif action_id == "timeout":
        updated["expires_at"] = int(time.time() * 1000) + 3000
        updated["actions"] = []
        updated["kind"] = "permission_decision"
        atomic_write(state_path, json.dumps(updated, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
        return
    else:
        updated["context"] = "Review on screen"
    updated["actions"] = []
    updated["kind"] = "permission_decision"
    atomic_write(state_path, json.dumps(updated, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def state_is_ours(state_path, request_id):
    """False once a newer event (e.g. the request answered on screen) has replaced state.json."""
    try:
        with open(state_path, "r", encoding="utf-8") as handle:
            return json.load(handle).get("request_id") == request_id
    except (FileNotFoundError, json.JSONDecodeError):
        return True


def awaiting_answer(state_path):
    """True while state.json shows buttons that are still waiting for a tap."""
    try:
        with open(state_path, "r", encoding="utf-8") as handle:
            state = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError):
        return False
    expires_at = int(state.get("expires_at") or 0)
    return bool(state.get("actions")) and (not expires_at or expires_at > int(time.time() * 1000))


def wait_for_response(base_dir, state_path, state, request_id, wait_ms, stop_waiting=None):
    """Polls for responses/<request_id>.json written by the Touch Bar app.

    Returns the response, or None on timeout, as soon as `stop_waiting()` is true, or once a
    newer event has replaced state.json (never write the old state back over it).
    """
    deadline = time.time() + wait_ms / 1000
    path = response_path(base_dir, request_id)
    last_refresh = time.time()

    while time.time() < deadline:
        if not state_is_ours(state_path, request_id):
            return None

        # Refresh expires_at every 5 seconds so the Touch Bar keeps showing the buttons
        now = time.time()
        if now - last_refresh >= 5:
            refreshed = dict(state)
            refreshed["expires_at"] = int((now + DEFAULT_EXPIRES_MS / 1000) * 1000)
            atomic_write(state_path, json.dumps(refreshed, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
            last_refresh = now

        if stop_waiting and stop_waiting():
            return None

        try:
            with open(path, "r", encoding="utf-8") as response_file:
                response = json.load(response_file)
        except (FileNotFoundError, json.JSONDecodeError):
            time.sleep(POLL_INTERVAL_SECONDS)
            continue

        if response.get("request_id") != request_id:
            time.sleep(POLL_INTERVAL_SECONDS)
            continue

        return response

    return None


def touch_bar_app_running(base_dir):
    """The Touch Bar app records its pid in frontmost.json; without it nothing can show a question."""
    try:
        with open(os.path.join(base_dir, "frontmost.json"), "r", encoding="utf-8") as handle:
            os.kill(int(json.load(handle)["app_pid"]), 0)
        return True
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        return False


def log_question(base_dir, row):
    with open(os.path.join(base_dir, "questions.jsonl"), "a", encoding="utf-8") as log_file:
        log_file.write(json.dumps(row, ensure_ascii=False) + "\n")


def pending_question_path(base_dir):
    return os.path.join(base_dir, "pending-question.json")


def active_question_path(base_dir):
    return os.path.join(base_dir, "active-question.json")


def question_owns_stop(base_dir, session_id):
    """True when this turn ended with a question, so the Stop state belongs to the question hook."""
    for path in (pending_question_path(base_dir), active_question_path(base_dir)):
        try:
            with open(path, "r", encoding="utf-8") as handle:
                if json.load(handle).get("session_id") == session_id:
                    return True
        except (FileNotFoundError, json.JSONDecodeError):
            continue
    return False


def remember_question(base_dir, event, now_ms):
    """PreToolUse of the next-step box: keep its question for the Stop hook. Nothing waits here."""
    tool_input = event.get("tool_input") or {}
    ask = str(tool_input.get("ask") or "").strip()
    # Only reply buttons carry a label; app actions (commit, create PR...) are left to the screen.
    labels = [
        str(action["label"])
        for action in tool_input.get("actions") or []
        if isinstance(action, dict) and action.get("label")
    ][:MAX_QUESTION_CHOICES]

    path = pending_question_path(base_dir)
    if not ask or not labels:
        if os.path.exists(path):
            os.unlink(path)
        return

    question = {"session_id": event.get("session_id"), "ask": ask, "labels": labels, "at": now_ms}
    atomic_write(path, json.dumps(question, ensure_ascii=False, indent=2) + "\n")


def ask_pending_question(base_dir, state_path, event, now_ms):
    """Background Stop hook (asyncRewake): mirror the turn's question on the Touch Bar.

    The turn has already ended, so Claude desktop shows its box at the same time. A tap returns
    a message that wakes Claude (exit code 2). Answering on screen starts a new turn, which
    replaces state.json and withdraws the question here. Returns the message, or None.
    """
    active = active_question_path(base_dir)
    try:
        os.replace(pending_question_path(base_dir), active)
        with open(active, "r", encoding="utf-8") as handle:
            question = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError):
        return None

    try:
        if question.get("session_id") != event.get("session_id"):
            return None
        if now_ms - int(question.get("at") or 0) > QUESTION_MAX_AGE_MS:
            return None

        ask = question["ask"]
        request_id = str(uuid.uuid4())
        if not touch_bar_app_running(base_dir):
            log_question(base_dir, {"request_id": request_id, "asked_at": now_ms, "ask": ask, "skipped": "touch bar app not running"})
            return None

        actions = [{"id": f"choice_{index}", "label": label} for index, label in enumerate(question["labels"])]
        actions.append({"id": "screen", "label": "On screen"})
        state = {
            "version": 1,
            "request_id": request_id,
            "session_id": event.get("session_id") or "unknown",
            "updated_at": now_ms,
            "expires_at": now_ms + DEFAULT_EXPIRES_MS,
            "kind": "NextStepQuestion",
            "context": ask[:80],
            "risk": "low",
            "actions": actions,
        }
        atomic_write(state_path, json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
        log_question(base_dir, {"request_id": request_id, "asked_at": now_ms, "ask": ask})

        response = wait_for_response(base_dir, state_path, state, request_id, question_wait_ms())
        action_id = (response or {}).get("action_id") or ""
        label = (response or {}).get("action_label") or ""
        withdrawn = response is None and not state_is_ours(state_path, request_id)

        # No "ended" line for a request_id means the hook was cut off while waiting.
        outcome = action_id or ("answered elsewhere" if withdrawn else "timeout")
        log_question(base_dir, {"request_id": request_id, "ended_at": int(time.time() * 1000), "outcome": outcome})

        if not withdrawn:
            finished = dict(state)
            finished["actions"] = []
            finished["kind"] = "question_answered"
            finished["expires_at"] = int(time.time() * 1000) + 3000
            finished["context"] = f"Sent: {label}" if action_id.startswith("choice_") else "Answer on screen"
            atomic_write(state_path, json.dumps(finished, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

        if not action_id.startswith("choice_"):
            return None
        return f"The user chose \u300c{label}\u300d on the Touch Bar, answering your question: {ask}"
    finally:
        if os.path.exists(active):
            os.unlink(active)


def main():
    base_dir = os.environ.get("CLAUDE_TOUCHBAR_DIR") or os.path.expanduser("~/.claude-touchbar")
    os.makedirs(base_dir, exist_ok=True)

    raw = sys.stdin.read()
    try:
        event = json.loads(raw)
    except json.JSONDecodeError:
        return

    now_ms = int(time.time() * 1000)
    is_stop = event.get("hook_event_name") == "Stop"
    state_path = os.path.join(base_dir, "state.json")

    # `touchbar-hook.sh question` runs as a separate asyncRewake Stop hook (see HOOK_SETUP.md).
    if "question" in sys.argv[1:]:
        if is_stop:
            message = ask_pending_question(base_dir, state_path, event, now_ms)
            if message:
                sys.stderr.write(message)
                sys.exit(2)
        return

    expires_ms = now_ms + (3000 if is_stop else DEFAULT_EXPIRES_MS)
    request_id = str(uuid.uuid4())

    last_event_path = os.path.join(base_dir, "last-event.json")
    log_path = os.path.join(base_dir, "events.jsonl")
    stored_event = sanitized_event(event)

    atomic_write(
        last_event_path,
        json.dumps(stored_event, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    )

    with open(log_path, "a", encoding="utf-8") as log_file:
        log_file.write(
            json.dumps(
                {"logged_at": now_ms, "event": stored_event},
                ensure_ascii=False,
                separators=(",", ":"),
            )
            + "\n"
        )

    if event.get("hook_event_name") == "PreToolUse" and event.get("tool_name") == QUESTION_TOOL:
        remember_question(base_dir, event, now_ms)

    risk = risk_level(event)
    state = {
        "version": 1,
        "request_id": request_id,
        "session_id": event.get("session_id") or "unknown",
        "updated_at": now_ms,
        "expires_at": expires_ms,
        "kind": event.get("hook_event_name") or "unknown",
        "context": context_text(event)[:80],
        "risk": risk,
        "actions": actions_for_state(event, risk),
        "raw_event_path": last_event_path,
    }

    # A turn that ends with a question leaves the Touch Bar to the question hook. A Notification
    # ("Claude needs your permission") is not progress: it must not replace a request that is
    # still waiting, or that request's hook would take it as answered elsewhere and give up.
    keep_current = (is_stop and question_owns_stop(base_dir, event.get("session_id"))) or (
        event.get("hook_event_name") == "Notification" and awaiting_answer(state_path)
    )
    if not keep_current:
        atomic_write(
            state_path,
            json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        )

    if event.get("hook_event_name") == "PermissionRequest":
        response = wait_for_response(base_dir, state_path, state, request_id, permission_wait_ms())
        if response is None:
            if state_is_ours(state_path, request_id):
                mark_decided(state_path, state, "timeout")
        else:
            mark_decided(state_path, state, response.get("action_id") or "")
            decision = decision_for_response(response)
            if decision:
                print(json.dumps(decision, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
