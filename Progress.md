# Claude Code Touch Bar Companion Progress

## 记录日期

2026-06-08

## 当前阶段

当前处于研究原型 / MVP 阶段。核心目标已经从“Touch Bar 能不能显示 Claude Code 状态”推进到“Touch Bar 能不能真实参与 Claude Code 权限决策”。

目前结论：真实 `PermissionRequest` 的核心闭环已经跑通，且不依赖键盘注入。

```text
Claude Code PermissionRequest
  -> project hook writes ~/.claude-touchbar/state.json
  -> BetterTouchTool reads state and renders Touch Bar
  -> user taps Yes / No / All edits / Review
  -> btt_action.py writes ~/.claude-touchbar/responses/<request_id>.json
  -> hook returns structured allow / deny / updatedPermissions
  -> Claude Code continues, denies, or applies session-scoped edit permission
```

当前实现不模拟方向键、回车或焦点窗口输入。权限结果通过 Claude Code `PermissionRequest` hook 的结构化输出返回。

## 已完成的关键验证

- Claude Code hooks 可以捕获真实 `PermissionRequest`。
- 真实 `Read` 权限请求可以显示到 Touch Bar。
- Touch Bar `Yes` 可以让 Claude Code 继续执行。
- Touch Bar `No` 可以拒绝 Claude Code 工具调用。
- Create / edit 权限请求在 Claude Code 提供 session edit suggestion 时，可以显示 `Yes / All edits / No`。
- `All edits` 会通过 `updatedPermissions` 回传 Claude Code，等价于选择 “Yes, allow all edits during this session”。
- BTT 四个小组件可以读取 `state.json` 并显示：

```text
[Context] [Action 1] [Action 2] [Action 3]
```

- 第一个 Touch Bar item 作为上下文摘要，不是批准按钮。
- BTT action 点击后可以写入 `~/.claude-touchbar/actions.jsonl`。
- 对活跃 `PermissionRequest`，BTT action 点击会写入 `~/.claude-touchbar/responses/<request_id>.json`。
- 状态过期后，BTT 不会执行旧 action。
- 高风险或未知风险不会显示一键 `Yes`。

## 当前按钮逻辑

`Read` 权限请求：

```text
Yes / Yes all session / No
```

其他常规低风险 / 中风险权限请求：

```text
Yes / No / Review
```

Create / edit 请求，并且 Claude Code 提供 `acceptEdits` session suggestion：

```text
Yes / All edits / No
```

高风险请求：

```text
Review / No
```

按钮含义：

- `Yes`：返回 `behavior: allow`。
- `No`：返回 `behavior: deny`。
- `All edits`：返回 `behavior: allow` 和 `updatedPermissions`。
- `Review`：不批准请求，hook 不返回 decision，让 Claude Code 回到主屏幕确认流程。

## 当前上下文摘要

Touch Bar 第一个 item 显示短摘要，不显示完整原始事件。

示例：

```text
Read PRD_中文.md
Create permission-edit-test.md
Write config.json
Edit TODO.md
Run Python scripts/check.py
Run npm test
Run pytest tests/foo.py
Delete touchbar-permission-test.md
```

当前 Bash 命令不会默认完整显示到 Touch Bar：

```text
python3 scripts/check.py  ->  Run Python scripts/check.py
npm test                  ->  Run npm test
pytest tests/foo.py       ->  Run pytest tests/foo.py
rm file.md                ->  Delete file.md
unknown-long-command ...  ->  Run unknown-long-command
```

未知 Bash 命令只显示命令名，不显示完整参数和长路径。

## 风险规则

当前风险分级：

- `low`
  - 普通 `Read`。
  - 常规低风险 Bash 请求。
  - `Read` 显示 `Yes / Yes all session / No`。

- `medium`
  - `Write` / `Edit` / `MultiEdit`。
  - 项目内明确单文件 `rm`。
  - 允许显示 `Yes / No / Review`。
  - 如果存在 session edit suggestion，显示 `Yes / All edits / No`。

- `high`
  - `sudo`
  - `rm -rf`
  - 递归删除
  - 通配符删除
  - 目录删除
  - 项目外删除
  - `chmod -R`
  - `chown -R`
  - `curl | sh`
  - `wget | sh`
  - `~/.ssh`
  - `/Library`
  - `/System`
  - 只显示 `Review / No`。

- `unknown`
  - 无法判断风险的状态。
  - 不允许直接批准。

风险判断在 hook 层和 action 层都做。即使状态文件里被写入 direct action，`scripts/btt_action.py` 也会阻止高风险 / 未知风险的一键批准。

## 当前文件状态

- `.claude/settings.local.json`
  - 注册项目本地 hooks。
  - 临时配置 `permissions.ask: ["Read"]`，用于强制读文件触发权限请求。
  - `PermissionRequest` hook timeout 为 25 秒，给用户时间点击 Touch Bar。
  - 同时注册 `Notification`、`PreToolUse`、`PostToolUse`、`PostToolUseFailure`、`Stop`。

- `.claude/hooks/touchbar-hook.sh`
  - Claude Code 调用的 shell wrapper。
  - 调用 Python hook，并始终安全退出。

- `.claude/hooks/touchbar_hook.py`
  - 读取 hook JSON。
  - 写入 `state.json`、`last-event.json`、`events.jsonl`。
  - 为 `PermissionRequest` 生成 `request_id`。
  - 等待 BTT 写入 response 文件。
  - 返回 Claude Code 官方结构化 allow / deny / updatedPermissions decision。
  - 负责路径缩短、Bash 摘要、`rm` 风险判断和日志脱敏。

- `scripts/btt_state.py`
  - BTT 动态标题脚本。
  - 读取 `~/.claude-touchbar/state.json`。
  - 输出 `context`、`action-label`、`action-id`、`kind` 或 `risk`。
  - 状态缺失或过期时返回 `CC Ready` 或空 action。

- `scripts/btt_action.py`
  - BTT 点击动作脚本。
  - 检查 JSON、过期时间和 action 是否存在。
  - 对 `PermissionRequest` 写入 response 文件。
  - 记录点击到 `actions.jsonl`。
  - 对高风险 / 未知风险 direct action 做二次阻断。

- `docs/HOOK_SETUP.md`
  - 记录 hook 安装、输出文件、PermissionResponse 流程和 `All edits` 测试。

- `docs/BTT_SETUP.md`
  - 记录 BTT 四个小组件配置、刷新间隔、action 脚本、预期状态和手动检查方式。

- `ONE_PAGE_中文.md` / `ONE_PAGE.md`
  - 记录项目一页说明、核心价值、当前能力和下一步。

- `PRD_中文.md`
  - 记录完整 PRD、信息架构、安全边界、MVP 完成标准和路线。

- `TODO.md`
  - 记录阶段性任务、验收标准、暂不做范围和开放问题。

## BTT 当前配置

Touch Bar 使用 4 个 Shell Script / Task Widget：

```text
[Context] [Action 1] [Action 2] [Action 3]
```

Context 脚本：

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_state.py context
```

Action 1 标题：

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_state.py action-label 0
```

Action 1 点击：

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_action.py 0
```

Action 2 标题：

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_state.py action-label 1
```

Action 2 点击：

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_action.py 1
```

Action 3 标题：

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_state.py action-label 2
```

Action 3 点击：

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_action.py 2
```

测试阶段建议 BTT 脚本执行间隔设为 1-2 秒。

## 当前状态格式

`~/.claude-touchbar/state.json` 示例：

```json
{
  "version": 1,
  "request_id": "uuid",
  "session_id": "claude-session-id",
  "updated_at": 1780000000000,
  "expires_at": 1780000030000,
  "kind": "PermissionRequest",
  "context": "Read PRD_中文.md",
  "risk": "low",
  "actions": [
    { "id": "allow", "label": "Yes" },
    {
      "id": "allow_session_read",
      "label": "Yes all session",
      "updated_permissions": [
        {
          "behavior": "allow",
          "destination": "session",
          "rules": [
            { "toolName": "Read", "ruleContent": "//Users/carson/Desktop/code/claude-touchbar-companion/**" }
          ],
          "type": "addRules"
        }
      ]
    },
    { "id": "deny", "label": "No" }
  ],
  "raw_event_path": "/Users/carson/.claude-touchbar/last-event.json"
}
```

Create / edit 请求在存在 session edit suggestion 时会使用：

```json
{
  "actions": [
    { "id": "allow", "label": "Yes" },
    {
      "id": "allow_session_edits",
      "label": "All edits",
      "updated_permissions": [
        { "destination": "session", "mode": "acceptEdits", "type": "setMode" }
      ]
    },
    { "id": "deny", "label": "No" }
  ]
}
```

## 当前已知限制

- `Stop` 状态当前会显示 `Claude done`，但代码仍可能生成 `Continue / Stop` action；这两个 action 还没有真实控制 Claude Code，下一步应隐藏。
- 当前只验证单 session 工作流，没有实现多 session 管理。
- 当前没有实现 iTerm2 / Terminal 焦点保护，因为不使用键盘注入；如果后续接任何按键动作，需要重新设计焦点保护。
- `permissions.ask: ["Read"]` 是为了测试强制触发权限请求，后续应移除或收窄。
- BTT 1-2 秒刷新长期稳定性仍需继续观察。
- 还没有完整 2 分钟 demo checklist。

## 下一步建议

1. 隐藏 `Stop` 状态未实现 action，只显示 `Claude done`。
2. 做一轮真实测试矩阵：
   - `Read file` -> `Yes`
   - `Read file` -> `No`
   - `Write/Create file` -> `All edits`
   - `rm 项目内单文件` -> `Yes`
   - `rm -rf` -> `Review / No`
   - `python3 ...` -> 短摘要显示
3. 准备 2 分钟 demo checklist。
4. 移除或收窄临时 `permissions.ask: ["Read"]`。
5. 视需要加入轻量研究日志字段，但避免保存完整代码、prompt 或 assistant message。
