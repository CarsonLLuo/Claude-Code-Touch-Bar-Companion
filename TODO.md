# Claude Code Touch Bar Companion TODO

## 更新日期

2026-06-08

## 当前目标

完成一个窄范围 MVP：真实 Claude Code 权限请求能通过 Touch Bar 显示、确认、拒绝，并保持足够安全边界。

首版不追求完整产品化，不解析完整 TUI，不支持多终端和多 session，不使用键盘注入。

当前核心链路已跑通。剩余工作重点是：隐藏未实现 action、整理 demo、移除或收窄测试用权限配置、继续观察 BTT 刷新稳定性。

## P0：下一步必须完成

- [ ] 隐藏未实现的 `Stop` actions
  - 验收：`Stop` 只显示 `Claude done`，不显示尚未实现的 `Continue / Stop` action。

- [ ] 完成真实测试矩阵
  - 验收：以下场景均可稳定复现并符合预期：
    - `Read file` -> Touch Bar `Yes`
    - `Read file` -> Touch Bar `No`
    - `Write/Create file` -> Touch Bar `All edits`
    - 项目内单文件 `rm` -> Touch Bar `Yes`
    - `rm -rf` -> Touch Bar `Review / No`
    - `python3 ...` -> Touch Bar 短摘要

- [ ] 准备 2 分钟 demo checklist
  - 验收：从启动 Claude Code 到完成权限请求、拒绝、All edits、删除测试、高风险 Review 的流程可以在 2 分钟内稳定演示。

- [ ] 移除或收窄临时 `permissions.ask: ["Read"]`
  - 验收：不再为了测试而让所有 `Read` 都请求权限，或改成更窄的测试规则。

## Phase 0：能力验证

- [x] 确认可用环境
  - 验收：macOS、Touch Bar、Claude Code、BetterTouchTool 均可用。

- [x] 确认 Claude Code hooks 事件格式
  - 验收：能捕获一次真实 `PermissionRequest`，并记录 hook 输入 JSON。

- [x] 确认确认流程回传方式
  - 验收：使用 hook response 文件 + `PermissionRequest` structured decision，不使用 keybinding 或键盘注入。

- [x] 确认 BTT 能稳定刷新 Touch Bar 文案
  - 验收：修改本地 JSON 后，Touch Bar 能刷新显示 context 和 action。

## Phase 1：BTT Touch Bar 小组件

- [x] 创建 4 个 Touch Bar 小组件
  - 布局：`[Context] [Action 1] [Action 2] [Action 3]`。
  - 验收：Context 和 Action 标题均由 `scripts/btt_state.py` 动态读取。

- [x] 配置 action 点击脚本
  - 验收：Action 1/2/3 点击后调用 `scripts/btt_action.py 0/1/2`。

- [x] 验证点击日志
  - 验收：点击 Touch Bar action 后写入 `~/.claude-touchbar/actions.jsonl`。

## Phase 2：state.json 驱动 Touch Bar

- [x] 定义首版状态文件格式
  - 默认路径：`~/.claude-touchbar/state.json`。
  - 必需字段：`version`、`request_id`、`session_id`、`updated_at`、`expires_at`、`kind`、`context`、`risk`、`actions`。

- [x] 实现 atomic write
  - 验收：先写临时文件，再 rename 到正式状态文件。

- [x] 实现 BTT 动态标题读取
  - 验收：Touch Bar 显示 `[Context] [Action 1] [Action 2] [Action 3]`。

- [x] 实现 action 执行前检查
  - 验收：JSON 无效、action 不存在、状态过期、风险不允许时不写 response。

- [x] 实现 idle / expired 状态
  - 验收：无有效状态时显示 `CC Ready` 或空 action；过期状态无法触发旧 action。

## Phase 3：Claude Code hooks 接入

- [x] 编写 `PermissionRequest` hook
  - 验收：真实权限请求发生后，`state.json` 更新。

- [x] 映射低风险权限请求
  - 验收：Touch Bar 显示类似 `Read PRD_中文.md [Yes] [Yes all session] [No]`。

- [x] 完成真实 `Yes` / `No` 闭环
  - 验收：用户点击 Touch Bar 后，Claude Code 确实继续或拒绝。

- [x] 支持 session edit permission suggestion
  - 验收：`Write` / create 请求出现 Claude Code session edit suggestion 时，Touch Bar 显示 `Yes / All edits / No`，并通过 `updatedPermissions` 回传。

- [x] 接入基础状态事件
  - 事件：`Notification`、`PreToolUse`、`PostToolUse`、`PostToolUseFailure`、`Stop`。
  - 验收：事件可写入状态文件，并可映射为轻量状态。

- [ ] 隐藏未实现的 `Stop` actions
  - 验收：`Stop` 只显示 `Claude done`，不显示尚未实现的 `Continue / Stop` action。

## Phase 4：安全边界

- [x] 实现风险分级
  - 等级：`low`、`medium`、`high`、`unknown`。
  - 验收：`high` 和 `unknown` 不显示直接批准按钮。

- [x] 加入高风险关键词检查
  - 示例：`sudo`、`rm -rf`、`chmod -R`、`chown -R`、`curl | sh`、`wget | sh`、`~/.ssh`、`/Library`、`/System`。

- [x] 实现 `rm` 细分风险
  - 验收：项目内单文件删除为 `medium`，递归 / 通配符 / 目录 / 项目外删除为 `high`。

- [x] action 执行层重复检查风险
  - 验收：即使状态文件包含 direct action，高风险 / 未知风险也不会被一键批准。

- [x] 实现 Review handoff
  - 验收：`Review` 不批准请求，只让 Claude Code 回到主屏幕确认。

- [x] 实现日志脱敏
  - 验收：`events.jsonl` 和 `last-event.json` 不默认保存完整文件内容、prompt 或 assistant message。

## Phase 5：上下文摘要

- [x] 缩短文件路径显示
  - 验收：优先显示项目相对路径，长路径中间省略。

- [x] 调整按钮文案
  - 验收：`Read` 使用 `Yes / Yes all session / No`，create / edit session suggestion 使用 `Yes / All edits / No`，其他常规权限使用 `Yes / No / Review`。

- [x] 实现 Bash 命令摘要
  - 验收：`python3`、`npm test`、`pytest`、未知 Bash 命令不再完整显示命令串。

- [x] 实现删除命令摘要
  - 验收：`rm file.md` 显示为 `Delete file.md`。

- [x] 实现创建 / 写入摘要
  - 验收：`Write` 请求显示为 `Create file.md` 或 `Write file.md`。

## Phase 6：Demo 脚本

- [ ] 准备稳定 demo 项目
  - 验收：能稳定触发读取项目、拒绝读取、创建文件、All edits、单文件删除、高风险删除升级等场景。

- [ ] 准备 2 分钟 demo 流程
  - 流程：启动 Claude Code -> 触发权限请求 -> Touch Bar Yes -> 触发权限请求 -> Touch Bar No -> 创建文件 -> All edits -> 删除测试文件 -> 高风险命令 Review。

- [ ] 记录失败兜底路径
  - 验收：BTT 未刷新、状态过期、高风险升级、Review fallback 都有可解释行为。

## Phase 7：后续产品化候选

- [ ] 观察 BetterTouchTool 1-2 秒动态刷新长期稳定性
  - 验收：连续使用一段时间后，Touch Bar 文案不会明显卡住或落后。

- [ ] 考虑导出 BTT preset
  - 验收：新环境可以少量手动步骤复现四个小组件配置。

- [ ] 考虑增加轻量研究日志字段
  - 验收：只记录 action 类型、风险、耗时、是否 fallback，不记录完整代码、prompt 或 assistant message。

- [ ] 考虑多 session 区分
  - 验收：多个 Claude Code session 同时运行时，Touch Bar 不会显示错误 session 的请求。

## 暂不做

- [ ] 不解析完整终端 TUI。
- [ ] 不支持 diff viewer 内部导航和当前选中项识别。
- [ ] 不支持 `/config`、`/permissions` 等内部菜单。
- [ ] 不支持 autocomplete、`@` mention 菜单和用户逐字输入监听。
- [ ] 不支持多 session。
- [ ] 不支持 Terminal.app、Warp、tmux、zellij 的键盘注入控制。
- [ ] 不做原生 Swift / AppKit helper。
- [ ] 不做公开分发安装包。
- [ ] 不绕过 Claude Code 原有权限机制。
- [ ] 不在高风险或未知风险动作上提供一键批准。

## 关键开放问题

- [x] `PermissionRequest` hook 的实际输入字段是否足够生成安全摘要？
- [x] Touch Bar 点击后最可靠的回传路径是什么？
- [x] 是否需要依赖 Claude Code keybindings？
  - 结论：当前不需要，走结构化 hook decision。
- [x] 高风险判断放在 hook 层、action 层，还是两边都做？
  - 结论：两边都做。
- [ ] BetterTouchTool 动态刷新是否能长期稳定保持 1-2 秒？
- [ ] 是否需要为研究目的记录交互日志？
- [ ] 临时 `permissions.ask: ["Read"]` 后续应该删除还是收窄？
- [ ] 多 session 时如何避免 Touch Bar 状态串线？

## MVP 完成标准

- [x] 能捕获一次真实 Claude Code `PermissionRequest`。
- [x] Touch Bar 能显示对应上下文和 action。
- [x] 用户能通过 Touch Bar 完成 `Yes`。
- [x] 用户能通过 Touch Bar 完成 `No`。
- [x] 用户能通过 Touch Bar 完成 `All edits`。
- [x] 过期状态不会执行旧 action。
- [x] 高风险或未知风险 action 不会被一键批准。
- [x] 不使用键盘注入，因此不会把确认按键发到错误窗口。
- [ ] 未实现状态不会显示可点击 action。
- [ ] demo 可以在 2 分钟内稳定复现。
