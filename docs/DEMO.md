# Two-Minute Demo Checklist

Shows Claude Code permission requests being answered from the Touch Bar, with risk-aware buttons and no keystrokes injected.

## Before the demo

- [ ] Touch Bar app is running: `cd app && .build/debug/TouchBarCompanion` (`CC` in the menu bar and Control Strip)
- [ ] `~/.claude-touchbar/icon.png` is in place if you want the logo
- [ ] Start a fresh Claude Code session in this project, in **default** permission mode (not Auto, Accept Edits or Bypass)
- [ ] If your global settings allow all `Bash` (for example `"allow": ["Bash"]` in `~/.claude/settings.json`), add temporary `ask` rules to `.claude/settings.local.json` so the Bash steps still ask:

  ```json
  "ask": ["Bash(rm *)", "Bash(python3 scripts/*)"]
  ```

- [ ] `demo-notes.md` does not exist in the project root
- [ ] Terminal and Touch Bar are both visible to the audience (or mirror the Touch Bar with `screencapture -b`)

## Script

Order matters: `All edits` switches the session to accept edits, so do it after the file creation step.

| Time | Prompt to Claude Code | Touch Bar shows | Tap | What to point out |
| --- | --- | --- | --- | --- |
| 0:00 | (none) | Regular Touch Bar, `CC` in the Control Strip | | The companion stays out of the way until something needs an answer |
| 0:15 | "Create demo-notes.md with one line describing this project" | `Create demo-notes.md` · `Yes` `All edits` `No` | `Yes` | The bar pops up by itself; the file is created without touching the terminal |
| 0:35 | "Add a second line to demo-notes.md" | `Edit demo-notes.md` · `Yes` `All edits` `No` | `All edits` | Session-scoped permission is passed back through `updatedPermissions`; later edits no longer ask |
| 0:55 | "Run python3 scripts/btt_state.py context" | `Run Python scripts/btt_state.py` · `Yes` `No` `Review` | `Yes` | Long commands become short, glanceable labels |
| 1:15 | "Delete demo-notes.md" | `Delete demo-notes.md` · `Yes` `No` `Review` | `Yes` | A single project-local file counts as medium risk, so a one-tap Yes is offered |
| 1:30 | "Run rm -rf tmp-demo" | `Delete tmp-demo` · `Review on screen` `No` | `No` | High risk: no one-tap approval at all; Claude Code reports "Denied from Touch Bar" |
| 1:50 | (none) | Back to the regular Touch Bar | | Answers are structured hook output, not keystrokes; Claude Code's own prompt is still the fallback |

Optional, if time allows: tap `Review on screen` on a high-risk request to show that it hands the decision back to Claude Code's on-screen prompt instead of approving.

## After the demo

- [ ] Remove the temporary `ask` rules from `.claude/settings.local.json`
- [ ] Delete `demo-notes.md` if it is still there

## If something goes wrong

| Symptom | Likely cause |
| --- | --- |
| No Touch Bar popup, Claude Code just runs the tool | Permission mode is not default, or an `allow` rule covers the tool |
| Popup appears, then Claude Code shows its own prompt | No tap within 20 seconds; the hook timed out and fell back |
| Popup never appears, even with an on-screen prompt | App not running, or the hook is not registered in `.claude/settings.local.json` |
