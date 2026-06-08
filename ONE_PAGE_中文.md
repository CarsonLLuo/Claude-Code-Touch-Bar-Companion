# Claude Code Touch Bar Companion

## 一页项目说明 v0.2

### 项目概述

Claude Code 主要运行在终端 TUI 中。这个项目探索 MacBook Pro Touch Bar 是否可以成为 Claude Code 的第二交互界面，用来显示权限请求摘要、轻量状态和安全动作，让用户在不离开主屏幕上下文的情况下完成 `Yes`、`No`、`All edits` 或 `Review` 等低摩擦决策。

项目目标不是替代 Claude Code TUI，而是为 agentic coding workflow 增加一个低打断、低注意力成本的 companion interface。

### 当前已验证核心链路

```text
Claude Code PermissionRequest
        ↓
项目本地 hook 写入 ~/.claude-touchbar/state.json
        ↓
BetterTouchTool Touch Bar 小组件读取 state.json
        ↓
Touch Bar 显示 [Context] [Action 1] [Action 2] [Action 3]
        ↓
用户点击 Yes / No / All edits / Review
        ↓
btt_action.py 写入 ~/.claude-touchbar/responses/<request_id>.json
        ↓
hook 返回 Claude Code 结构化 allow / deny / updatedPermissions
        ↓
Claude Code 继续、拒绝或应用 session-scoped edit permission
```

当前实现不使用键盘注入，也不依赖 iTerm2 焦点发送按键。权限结果通过 Claude Code `PermissionRequest` hook 的结构化输出返回。

### Touch Bar UI

Touch Bar 使用四个小组件：

```text
[Context] [Action 1] [Action 2] [Action 3]
```

示例：

```text
Read PRD_中文.md                  [Yes] [Yes all session] [No]
Create permission-edit-test.md   [Yes] [All edits] [No]
Delete touchbar-test.md          [Yes] [No] [Review]
Delete tmp                       [Review] [No]
Run npm test                     [Yes] [No] [Review]
```

第一个 item 只显示当前请求摘要，不是操作按钮。它用于降低误批准风险。

### 当前能力

- 捕获真实 Claude Code `PermissionRequest`。
- 通过 Touch Bar 完成真实 `Yes` 和 `No` 闭环。
- 在 create / edit 请求中支持 `All edits`，等价于 Claude Code 的 “Yes, allow all edits during this session”。
- 对 `Read` 请求支持 session-scoped read approval。
- 对 `Read`、`Write`、`Bash`、`rm` 等请求生成短上下文摘要。
- 对 Bash 命令做摘要，不把完整命令和长路径塞进 Touch Bar。
- 对本地事件日志做基础脱敏，不默认保存完整文件内容、prompt 或 assistant message。
- 高风险或未知风险 action 不显示一键批准。

### 风险分级

当前规则：

- `low`
  - 普通 `Read`
  - 常规低风险 Bash 请求
  - `Read` 显示 `Yes / Yes all session / No`

- `medium`
  - `Write` / `Edit` / `MultiEdit`
  - 项目内明确单文件 `rm`
  - 显示 `Yes / No / Review` 或 `Yes / All edits / No`

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
  - 显示 `Review / No`

- `unknown`
  - 无法判断风险
  - 不允许直接批准

### 为什么值得做

LLM 编程助手会频繁请求用户做小决策，例如读取文件、创建文件、运行命令、删除临时文件或批准本轮编辑。这些决策重要但形式重复。Touch Bar 位于键盘上方，适合承载简短、即时、低注意力成本的确认动作。

核心研究问题：

> Touch Bar 能否成为 AI coding agent 的低注意力权限确认界面，并在降低交互摩擦的同时维持安全意识？

### 技术方案

当前 MVP 采用：

```text
Claude Code hooks
  -> .claude/hooks/touchbar_hook.py
  -> ~/.claude-touchbar/state.json
  -> BetterTouchTool Shell Script / Task Widget
  -> scripts/btt_action.py
  -> ~/.claude-touchbar/responses/<request_id>.json
  -> PermissionRequest hook decision
```

关键点：

- `state.json` 使用 atomic write。
- 每个 permission request 带 `request_id`。
- BTT 点击 action 后写 response 文件。
- hook 等待 response 文件，最多 20 秒。
- `Review` 不批准请求，回到 Claude Code 主屏幕确认。
- `All edits` 仅在 Claude Code 提供 `permission_suggestions` 中的 `acceptEdits` session suggestion 时显示。

### 仍不做

- 不解析完整终端 TUI。
- 不用 OCR 或像素识别。
- 不做 diff viewer 内部导航。
- 不控制 `/config`、`/permissions` 等内部菜单。
- 不监听 autocomplete、`@` mention 或逐字输入。
- 不支持多 session。
- 不做键盘注入控制。
- 不做原生 Swift / AppKit helper。
- 不做公开分发安装包。

### 下一步

1. 隐藏未实现的 `Stop` 状态 action，只显示 `Claude done`。
2. 准备 2 分钟 demo checklist。
3. 做真实测试矩阵：
   - `Read file` -> `Yes`
   - `Read file` -> `No`
   - `Write/Create file` -> `All edits`
   - `rm 项目内单文件` -> `Yes`
   - `rm -rf` -> `Review / No`
   - `python3 ...` -> 短摘要显示
4. 移除或收窄临时 `permissions.ask: ["Read"]`。
