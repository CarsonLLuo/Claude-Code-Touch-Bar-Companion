# Claude Code Touch Bar Companion PRD

## 1. 文档信息

- 产品名称：Claude Code Touch Bar Companion
- 文档类型：产品需求文档 PRD
- 文档语言：中文
- 当前版本：v0.2
- 更新日期：2026-06-08
- 当前阶段：研究原型 / MVP
- 目标平台：macOS，带 Touch Bar 的 MacBook Pro
- 当前 MVP 环境：macOS + Claude Code + BetterTouchTool

## 2. 项目背景

Claude Code 主要运行在终端 TUI 中。用户在 agentic coding workflow 中经常需要做出轻量但重要的确认，例如允许读取文件、创建文件、运行命令、删除临时文件、拒绝操作、或者允许本 session 内所有编辑。

这些确认频率高、操作集合小、文本结构重复，但会打断用户对主屏幕代码、diff、测试结果和 Claude 推理过程的注意力。

本项目希望探索 MacBook Pro Touch Bar 是否可以成为 Claude Code 的辅助交互界面，用来承载这类短时、明确、低注意力成本的操作。

核心研究问题：

> Touch Bar 能否成为 AI coding agent 的低注意力权限确认界面，并在降低交互摩擦的同时维持足够的用户安全意识？

## 3. 产品定位

Claude Code Touch Bar Companion 是一个 Claude Code companion interface 原型。它不替代 Claude Code TUI，也不尝试解析完整终端画面。

当前 MVP 通过 Claude Code hooks 捕获 `PermissionRequest`，把当前请求写入本地 `state.json`，由 BetterTouchTool 渲染 Touch Bar 小组件。用户点击 Touch Bar 后，BTT 写入 response 文件，hook 再通过 Claude Code 官方结构化决策返回 `allow`、`deny` 或 `updatedPermissions`。

当前实现不使用键盘注入，不依赖 iTerm2 焦点，也不通过方向键或回车模拟终端 UI 操作。

## 4. 目标用户

### 4.1 主要用户

- 使用 Claude Code 进行日常编程的开发者
- 希望加速 Claude Code 权限确认和轻量控制的 power user
- 对 AI-assisted coding workflow 感兴趣的 HCI / Interactive Media 研究者

### 4.2 次要用户

- 探索二级显示界面和触觉控制面的交互设计者
- 研究 AI agent 可控性、权限确认、安全交互的学生或研究人员

## 5. 用户问题

### 5.1 高频确认打断主任务

用户在 Claude Code 中工作时，经常需要处理读文件、写文件、运行命令、删除文件等小决策。这些决策本身不复杂，但频繁出现时会打断主屏幕注意力。

### 5.2 轻量决策占用主屏幕空间

权限 prompt 的主要操作通常只有 `Yes`、`No`、`Review` 或 `All edits`。主屏幕更适合承载上下文理解，而不是重复承载几个确认按钮。

### 5.3 Agent 控制缺少独立操作面

Claude Code 的主交互集中在终端里。用户缺少一个可以快速批准、拒绝或回到主屏幕查看的低摩擦控制面。

## 6. 当前 MVP 目标

MVP 需要证明：

1. Claude Code 的真实 `PermissionRequest` 可以被 hooks 捕获。
2. 当前结构化事件可以写入本地状态文件。
3. BetterTouchTool 可以根据状态动态更新 Touch Bar。
4. 用户可以通过 Touch Bar 对权限请求做出 `Yes` 或 `No`。
5. create / edit 请求在 Claude Code 提供 session edit suggestion 时，可以通过 `All edits` 应用 `updatedPermissions`。
6. Touch Bar UI 能展示足够短且明确的上下文，避免盲目批准。
7. 高风险或未知风险 action 不会显示一键 `Yes`。
8. 不使用键盘注入，避免把确认按键发送到错误窗口。

## 7. 当前已验证结论

- 真实 `PermissionRequest` 已捕获。
- 真实 `Read` 权限请求已通过 Touch Bar `Yes` 放行。
- 真实 `Read` 权限请求已通过 Touch Bar `No` 拒绝。
- create / edit 请求的 `permission_suggestions` 可用于 `All edits`。
- `All edits` 已验证能输出 `updatedPermissions`。
- BTT 四个小组件可以显示 `Context / Action 1 / Action 2 / Action 3`。
- Bash 命令已做短摘要，不默认显示完整命令。
- `rm` 单文件删除和高风险删除已做区分。
- 日志已做基础脱敏。

## 8. 非目标

第一版不做以下内容：

- 不替代 Claude Code TUI。
- 不解析完整终端 TUI 屏幕状态。
- 不做 OCR 或像素识别。
- 不做完整 diff review。
- 不支持 diff viewer 内部导航。
- 不控制 `/config`、`/permissions` 等内部菜单。
- 不监听 autocomplete、`@` mention 或用户逐字输入。
- 不做多 session 管理。
- 不支持 Terminal.app、Warp、tmux、zellij 的键盘注入控制。
- 不做原生 Swift / AppKit helper。
- 不做公开分发安装包。
- 不绕过 Claude Code 的权限机制。
- 不在高风险或未知风险动作上提供一键批准。

## 9. 核心交互流程

```text
Claude Code PermissionRequest
  ↓
.claude/hooks/touchbar_hook.py
  ↓
写入 ~/.claude-touchbar/state.json
  ↓
BetterTouchTool Shell Script / Task Widget 读取状态
  ↓
Touch Bar 显示 [Context] [Action 1] [Action 2] [Action 3]
  ↓
用户点击 Touch Bar action
  ↓
scripts/btt_action.py 写入 ~/.claude-touchbar/responses/<request_id>.json
  ↓
hook 读取 response 文件
  ↓
hook 返回 PermissionRequest structured decision
  ↓
Claude Code 执行 allow / deny / updatedPermissions
```

## 10. Touch Bar 信息架构

MVP 使用四个 Touch Bar 小组件：

```text
[Context] [Action 1] [Action 2] [Action 3]
```

### 10.1 Context

第一个 item 是请求摘要，不是 action。

示例：

```text
Read PRD_中文.md
Create permission-edit-test.md
Write config.json
Delete touchbar-test.md
Run npm test
Run Python scripts/check.py
```

### 10.2 Action

`Read` 权限请求：

```text
Yes / Yes all session / No
```

其他常规权限请求：

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

### 10.3 文案原则

- 与 Claude Code 当前权限 UI 保持一致，使用 `Yes` / `No`。
- 第一个 item 显示动作 + 对象，不显示完整命令。
- 长路径优先显示项目相对路径。
- 过长路径中间省略。
- 未知 Bash 命令只显示命令名，不显示所有参数。

## 11. 状态文件

默认路径：

```text
~/.claude-touchbar/state.json
```

示例：

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
    { "id": "deny", "label": "No" },
    { "id": "screen", "label": "Review" }
  ],
  "raw_event_path": "/Users/carson/.claude-touchbar/last-event.json"
}
```

Create / edit 请求在存在 `acceptEdits` session suggestion 时：

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

写入要求：

- 使用 atomic write。
- 每个 PermissionRequest 生成新的 `request_id`。
- 每个状态包含 `updated_at` 和 `expires_at`。
- 过期状态不可触发旧 action。

## 12. Response 文件

BTT 点击后写入：

```text
~/.claude-touchbar/responses/<request_id>.json
```

示例：

```json
{
  "request_id": "uuid",
  "session_id": "claude-session-id",
  "clicked_at": 1780000000000,
  "kind": "PermissionRequest",
  "risk": "medium",
  "action_id": "allow_session_edits",
  "action_label": "All edits",
  "updated_permissions": [
    { "destination": "session", "mode": "acceptEdits", "type": "setMode" }
  ]
}
```

hook 读取 response 后返回：

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedPermissions": [
        { "destination": "session", "mode": "acceptEdits", "type": "setMode" }
      ]
    }
  }
}
```

## 13. 风险分级

### 13.1 low

低风险，例如：

- 普通 `Read`
- 常规低风险 Bash 请求

行为：

```text
Yes / Yes all session / No
```

### 13.2 medium

中风险，例如：

- `Write`
- `Edit`
- `MultiEdit`
- 项目内明确单文件 `rm`

行为：

```text
Yes / No / Review
```

如果存在 `acceptEdits` session suggestion：

```text
Yes / All edits / No
```

### 13.3 high

高风险，例如：

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

行为：

```text
Review / No
```

### 13.4 unknown

无法识别风险时，不显示一键 `Yes`。

## 14. Bash 摘要规则

Bash 命令不默认完整显示。

示例：

```text
python3 scripts/check.py  ->  Run Python scripts/check.py
npm test                  ->  Run npm test
pytest tests/foo.py       ->  Run pytest tests/foo.py
rm file.md                ->  Delete file.md
unknown-long-command ...  ->  Run unknown-long-command
```

未知命令只显示命令名，不显示完整参数和路径。

## 15. 安全与隐私

### 15.1 安全原则

- Touch Bar 只加速上下文明确的 action。
- 高风险或未知风险不显示一键 `Yes`。
- `Review` 不批准请求，只回到主屏幕确认。
- `All edits` 只在 Claude Code 提供匹配 suggestion 时显示。
- 不绕过 Claude Code 原有权限机制。
- 不使用键盘注入。

### 15.2 隐私原则

- 本地状态文件只保存当前事件摘要和必要字段。
- `events.jsonl` 和 `last-event.json` 默认脱敏。
- 不默认保存完整文件内容、prompt 或 assistant message。
- 首版不上传任何数据到远程服务。

## 16. 当前文件结构

```text
.claude/settings.local.json
.claude/hooks/touchbar-hook.sh
.claude/hooks/touchbar_hook.py
scripts/btt_state.py
scripts/btt_action.py
docs/HOOK_SETUP.md
docs/BTT_SETUP.md
Progress.md
TODO.md
```

## 17. BetterTouchTool 配置

使用四个 Shell Script / Task Widget。

Context：

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

测试阶段建议刷新间隔为 1-2 秒。

## 18. 已知限制

- `Stop` 状态目前仍可能显示 `Continue / Stop`，但动作未真正接入。下一步应隐藏。
- 只验证了单 session。
- `permissions.ask: ["Read"]` 是临时测试配置，后续应移除或收窄。
- 还没有正式 demo checklist。
- BTT 长期 1-2 秒刷新稳定性仍需观察。

## 19. MVP 完成标准

已完成：

- [x] 捕获真实 `PermissionRequest`。
- [x] Touch Bar 显示权限上下文。
- [x] Touch Bar `Yes` 生效。
- [x] Touch Bar `No` 生效。
- [x] `All edits` 可通过 `updatedPermissions` 生效。
- [x] 过期状态不会执行旧 action。
- [x] 高风险或未知风险不会被一键批准。
- [x] 不使用键盘注入。

待完成：

- [ ] 未实现状态不显示可点击 action。
- [ ] 2 分钟 demo 可以稳定复现。

## 20. 下一步

1. 隐藏 `Stop` 状态下未实现的 `Continue / Stop` action。
2. 准备稳定 demo 项目和 2 分钟 demo checklist。
3. 做完整真实测试矩阵：
   - `Read file` -> `Yes`
   - `Read file` -> `No`
   - `Write/Create file` -> `All edits`
   - 项目内单文件 `rm` -> `Yes`
   - `rm -rf` -> `Review / No`
   - `python3 ...` -> 短摘要显示
4. 移除或收窄临时 `permissions.ask: ["Read"]`。
