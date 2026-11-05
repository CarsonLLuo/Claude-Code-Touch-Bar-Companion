# Claude Code Touch Bar Companion

<p align="right">
  <a href="README.md"><img src="https://img.shields.io/badge/English-111827?style=for-the-badge" alt="English"></a>
  <a href="README_%E4%B8%AD%E6%96%87.md"><img src="https://img.shields.io/badge/%E4%B8%AD%E6%96%87-2563EB?style=for-the-badge" alt="中文"></a>
</p>

![macOS](https://img.shields.io/badge/macOS-Touch%20Bar-111827?style=for-the-badge&logo=apple&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-Hooks-D97706?style=for-the-badge)
![Native Swift](https://img.shields.io/badge/Native-Swift%20App-F05138?style=for-the-badge&logo=swift&logoColor=white)
![No Keyboard Injection](https://img.shields.io/badge/No%20Keyboard%20Injection-Safe-16A34A?style=for-the-badge)

![Touch Bar 截图](image/README/1780981115328.png)

把 MacBook Pro Touch Bar 变成 Claude Code 的轻量权限控制台。

当 Claude Code 频繁询问读文件、写文件、运行命令、删除文件或本会话授权时，这个 companion 会把当前权限请求压缩成 Touch Bar 上的短摘要和几个动作按钮。你点一下，结果会通过 Claude Code 官方 `PermissionRequest` hook 结构化返回，不需要往终端里注入键盘输入。

> 范围说明：Touch Bar 现在由 [app/](app/) 里的原生 Swift 菜单栏 app 渲染。原来的 BetterTouchTool 配置保留为旧方案。

```text
Read PRD_中文.md                  [Yes] [Yes all session] [No]
Create permission-edit-test.md   [Yes] [All edits] [No]
Delete touchbar-test.md          [Yes] [No] [Review]
Delete tmp                       [Review on screen] [No]
Run npm test                     [Yes] [No] [Review]
```

## 为什么做它

Claude Code 很适合保持 coding flow，但 agentic coding 里仍然会反复出现一堆小决策：

- 要读这个文件吗？
- 要创建这个文件吗？
- 要运行这个命令吗？
- 要删除这个临时文件吗？
- 本会话允许全部编辑吗？

这些决策很小，但不该被忽略。Touch Bar 刚好适合承载这种低注意力、短动作、即时反馈的交互。

## 亮点

- **结构化 hook 闭环**：通过 Claude Code hooks 返回 `allow`、`deny` 和 `updatedPermissions`。
- **无键盘注入**：不往终端输入字符，也不依赖终端焦点。
- **原生 Touch Bar app**：轻量的 Swift 菜单栏 app 展示一个上下文 item 和最多三个彩色 action，只在需要回答时弹出，状态变化即时刷新，不轮询。
- **本会话授权**：`Read` 支持 `Yes all session`，edit suggestion 支持 `All edits`。
- **风险感知**：高风险请求不会出现一键批准，只保留 `Review on screen / No`。
- **短摘要**：长路径和 Bash 命令会被压缩成适合 Touch Bar 浏览的标签。
- **本地状态**：状态、日志和 response 都写在 `~/.claude-touchbar/`。

## 工作方式

```text
Claude Code PermissionRequest
        |
        v
.claude/hooks/touchbar_hook.py
        |
        v
~/.claude-touchbar/state.json
        |
        v
app/ TouchBarCompanion (Swift menu bar app)
        |
        v
~/.claude-touchbar/responses/<request_id>.json
        |
        v
Claude Code structured hook decision
```

## Touch Bar 布局

Swift app 渲染的布局：

```text
[x] [Logo Context] [Action 1] [Action 2] [Action 3]
```

`Context` 是白底的只读 item，显示 Claude Code 正在请求什么，不是批准按钮；前面可以显示 `~/.claude-touchbar/icon.png` 里的图标。Action 按含义上色：`Yes` 绿色，本会话授权蓝色，`No` 红色，Review 类灰色。

没有待回答的请求时，系统原本的 Touch Bar（包括 Esc）保持不变；Control Strip 里的 `CC` 按钮可以手动打开 companion bar。

编译和运行见 [docs/APP_SETUP.md](docs/APP_SETUP.md)。旧的 BetterTouchTool 配置见 [docs/BTT_SETUP.md](docs/BTT_SETUP.md)。

## 当前行为

| 请求 | Touch Bar actions |
| --- | --- |
| `Read` | `Yes / Yes all session / No` |
| 带 edit suggestion 的 `Write`、`Edit`、`MultiEdit` | `Yes / All edits / No` |
| 常规低/中风险请求 | `Yes / No / Review` |
| 高风险删除或 shell 命令 | `Review on screen / No` |
| 过期状态 | `CC Ready` |

`Review` / `Review on screen` 不会批准请求，只是把控制权交回 Claude Code 主屏幕权限流程。

## Claude Code 权限模式

Touch Bar Companion 的触发取决于你在 Claude Code 里使用的权限模式：

| 模式 | 会触发 Touch Bar？ | 说明 |
| --- | --- | --- |
| **默认（无模式）** | ✅ 需要审批时触发 | Write、Edit、Bash 通常需要审批；日常不建议强制项目内普通 `Read` 审批 |
| **Accept Edits** | ⚠️ 部分触发 | Write/Edit 自动批准，Bash 仍然触发 |
| **Auto Mode** | ⚠️ 部分触发 | CC 自动放行低风险操作，不确定的仍触发 |
| **Bypass Permissions** | ❌ 不触发 | 所有操作自动批准，hook 不介入 |
| **Plan Mode** | ❌ 不触发 | 只规划不执行，没有工具调用 |

**推荐的日常使用方式**：不要强制项目内普通 `Read` 反复审批，把 Touch Bar 留给 `Write`、`Edit`、`Bash`、删除等有副作用的操作。

**推荐的测试/demo 方式**：使用默认模式，并可临时添加 `permissions.ask: ["Read"]`，方便稳定复现 `Read` 的 Touch Bar flow。

## 快速开始

1. 把这个项目放在 Claude Code workspace 里。
2. 确认 [.claude/settings.local.json](.claude/settings.local.json) 注册了项目本地 hook。
3. 编译并运行 Swift app：`cd app && swift build && .build/debug/TouchBarCompanion`（见 [docs/APP_SETUP.md](docs/APP_SETUP.md)）。
4. 触发一个 Claude Code 权限请求。
5. 在 Touch Bar 上点击对应 action。

日常使用时，项目内普通 `Read` 不应该反复要求确认。如果需要测试或演示 `Read` flow，可以临时在本地 Claude Code 配置里加入 `permissions.ask: ["Read"]`，测试结束后再移除。

## 项目结构

```text
.claude/hooks/touchbar_hook.py   # Claude Code hook: 写 state 并返回 decision
.claude/hooks/touchbar-hook.sh   # hook shell wrapper
app/                             # 原生 Swift Touch Bar app（SwiftPM）
scripts/btt_state.py             # 旧方案：BetterTouchTool 动态标题读取器
scripts/btt_action.py            # 旧方案：BetterTouchTool 点击动作写入器
scripts/start_claude_iterm2.sh   # 旧方案：点击 BTT Context item 启动 Claude Code
docs/APP_SETUP.md                # Swift app 配置指南
docs/BTT_SETUP.md                # 旧方案：BetterTouchTool 配置指南
docs/HOOK_SETUP.md               # hook 行为和手动测试
ONE_PAGE.md                      # 项目 one-pager
README.md                        # English README
README_中文.md                    # 中文 README
PRD_中文.md                       # 中文 PRD
TODO.md                          # 实现 checklist
Progress.md                      # 当前进度记录
```

## 安全模型

这个 companion 保持保守：

- 高风险或未知风险 action 不能从 Touch Bar 直接批准。
- `Review` 是 handoff，不是 approval。
- 事件日志会脱敏 prompt、assistant message 和文件内容。
- `state.json` 使用 atomic write。
- 每个权限请求都有新的 `request_id`。
- 如果按钮画出来之后请求已经变了，点击会被忽略。

它是 Claude Code 主权限 UI 的 companion，不是替代品。

## 手动检查

查看当前 Touch Bar 状态：

```sh
python3 -m json.tool ~/.claude-touchbar/state.json
```

查看最近一次点击：

```sh
tail -n 1 ~/.claude-touchbar/actions.jsonl
```

查看 pending response 文件：

```sh
find ~/.claude-touchbar/responses -maxdepth 1 -type f -print
```

## Roadmap

- 在 Swift app 上跑完真实权限测试矩阵，准备两分钟 demo。
- 通过配置文件自定义 Touch Bar 按钮。
- 增加 SwiftUI 设置窗口，用 GUI 自定义按钮。
- 开源分发：Swift 版 hook（去掉 Python 依赖）、Homebrew cask。

详见 [TODO.md](TODO.md)。

## 状态

MVP 已经可以在 macOS Touch Bar 上处理真实 Claude Code 权限请求。原生 Swift app 已经取代 BetterTouchTool 成为渲染层。
