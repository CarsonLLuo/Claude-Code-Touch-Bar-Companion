# Claude Code Touch Bar Companion

## 更新日期

2026-11-06

## 当前状态

MVP 核心链路已跑通。`PermissionRequest` hook 端到端可用，Touch Bar 显示权限摘要、风险分级按钮，用户点击后通过结构化 hook decision 回传 Claude Code。

渲染层已从 BTT 换成原生 Swift 菜单栏 app，由 LaunchAgent 后台常驻、开机自启。阶段 2 的用量显示已完成；另外新增了 Claude 桌面 app"下一步"提问上 Touch Bar，以及"一次点击提交推送"（由权限请求作为唯一的确认）。下一步是卡通小角色，以及提交推送权限请求的提问框样式（待决定）。

## MVP 完成标准

- [x] 捕获真实 Claude Code `PermissionRequest`
- [x] Touch Bar 显示上下文摘要和 action 按钮
- [x] `Yes` / `No` / `All edits` 闭环可用
- [x] 过期状态不触发旧 action
- [x] 高风险 / 未知风险不显示一键批准
- [x] 不使用键盘注入
- [x] 权限请求等待期间按钮持续显示（expires_at 动态续期）
- [x] 超时后立即切回 CC Ready（不挂旧状态）
- [x] Stop 事件后快速切回 CC Ready（3 秒过期）
- [x] Stop 只显示 Claude done，不提供动作按钮
- [ ] demo 可在 2 分钟内稳定复现

## 路线图

### 阶段 1：Swift 菜单栏 app 替代 BTT（只做渲染）

- [x] 用 SwiftPM 搭建菜单栏 app（accessory 模式，无 Dock 图标）→ `app/`，说明见 `docs/APP_SETUP.md`
- [x] 通过私有 API（`NSTouchBar.presentSystemModalTouchBar` / `DFRElementSetControlStripPresenceForIdentifier`）显示 Touch Bar，参考 MTMR 的 `TouchBarPrivateApi.h`
- [x] 渲染 `[Context] [Action 1] [Action 2] [Action 3]` 四个按钮；有权限请求时自动弹出，结束后让回系统 Touch Bar
- [x] 监听 `~/.claude-touchbar/` 目录变化即时刷新，替代 1-2 秒轮询
- [x] 点击按钮写 `responses/<request_id>.json` 和 `actions.jsonl`，沿用现有文件协议；request_id 不一致时忽略点击
- [x] Python hook 暂不改动
- [ ] 移植 BTT 的"点 Context 启动 iTerm2 + Claude"（可选）
- [x] 完成真实测试矩阵（不安装 BTT，2026-11-05 真机通过）
  - [x] 测试/demo 模式下 `Read` → Yes / No
  - [x] `Write/Create` → All edits
  - [x] 项目内单文件 `rm` → Yes
  - [x] `rm -rf` → Review on screen / No
  - [x] `python3 ...` → 短摘要
- [x] 准备 2 分钟 demo checklist → `docs/DEMO.md`
- [ ] 按 `docs/DEMO.md` 完整彩排一遍，确认 2 分钟内稳定复现

验收：卸载 BTT 后测试矩阵全部通过，demo 可稳定复现。

### 阶段 2：用量显示 + 卡通形象（P0）

- [x] 用量显示（会话 5 小时 / 周）：2026-11-05 用真实账号数据在真机上验证三层显示
  - 主数据源（可选开启，菜单栏 `CC` → Fetch Usage from Claude Account）：app 每 5 分钟调用 `/usage` 背后的未公开接口 `api.anthropic.com/api/oauth/usage`，token 通过 `/usr/bin/security` 从钥匙串读取，只在内存里用一次，不续期；覆盖终端、桌面 app、claude.ai 的用量
  - 备用数据源：官方 status line stdin JSON 的 `rate_limits.five_hour` / `rate_limits.seven_day`（只在终端会话中运行，桌面 app 不触发）
  - 后续可用：接口还返回 `seven_day_breakdown`（Claude Code / Chats / Cowork 各占多少）和官方 `severity`，可以放进按需层
  - 新增 status line 脚本，把数据原子写入 `~/.claude-touchbar/usage.json`，同时输出一行终端状态文字
  - app 监听 `usage.json`
  - 三层分工（权限可以打断，用量永远不打断）：
    - 常驻层（Control Strip）：小角色 + 一条短的分段电池，只显示当前更紧的窗口；标签写 `5h` / `7d`，不写 Session，避免和对话混淆
    - 按需层（点 Control Strip 打开 companion bar）：5h 和 7d 两条拉长的分段电池，各带剩余百分比和重置时间（5h 倒计时、7d 重置日）
    - 打断层（权限请求）：平时不显示用量；5h 剩余 ≤ 10% 时在 context 里加低电量角标
  - 电池样式：显示剩余而不是已用；5h 剩余 ≤ 30% 黄、≤ 10% 红；7d 剩余 ≤ 20% 或用得比时间进度快为黄、≤ 5% 红；两者一样紧时优先 5h
  - F1 minisector 分段：5h 分 10 格（每格 30 分钟），7d 分 7 格（每天）；每格按这一段用量相对平均份额上色（≤ 1× 绿、≤ 1.5× 黄、> 1.5× 红），当前格白框，未到的格深灰，没有数据的格斜纹
  - 分段需要历史：status line 脚本把每次快照带时间戳追加到 `~/.claude-touchbar/usage-history.jsonl`，按时间段算差值；切分和上色逻辑放 `CompanionCore`，写单元测试
  - 数据过时（例如 30 分钟没有新快照）时整体变灰
  - 5h 窗口 15 分钟内重置时，常驻电池旁显示充电闪电
  - 限制：`rate_limits` 只有 Pro / Max / Ultra 订阅且首次 API 响应后才有，API key 用户只能显示花费；只在终端 CLI 会话中运行，空闲时不刷新；多会话时上下文和花费只反映最近活跃的会话
  - 历史数据的限制：claude.ai 网页 / 桌面 app 和 Claude Code 共用额度，其他地方的用量会被记到下一次快照所在的格子；没开 Claude Code 的时段没有快照，只能画斜纹
  - 实测：Control Strip 每格约 50pt，横排会被整体缩小；改为两行（上 `5h 47`，下细分段电池）
  - 实测：按需层 context 胶囊 + 两条 170pt 电池放不下，7d 被系统隐藏；改为 context 只显示 logo、电池 130pt
  - 窗口的第一个快照如果不在第一格，只作为基线，不把之前的用量记到当前格
- [ ] 卡通形象：Touch Bar 上的动画小角色，跟着 Claude Code 状态动
  - 状态映射（基于 hook 已有事件）：空闲 → 睡觉 / 眨眼；`PreToolUse` → 原地小跑；`PermissionRequest` → 跳起来挥手（替代 context 前的 logo）；`Stop` → 转圈庆祝；`PostToolUseFailure` → 缩一下
  - 位置：平时在 Control Strip 原地动，不占主区域、不挡 Esc；弹出权限请求时出现在 companion bar 里，可以走几步
  - 不为动画常驻主区域：会盖住 Esc，而自制 Esc 按钮属于键盘注入
  - 素材：Clawd 是 Anthropic 的形象，不放进仓库；app 从 `~/.claude-touchbar/` 读用户提供的 GIF / 精灵图；开源版另做原创像素角色作默认形象
  - 功耗：低帧率，只在状态变化时动，空闲基本静止

验收：订阅账号下 Touch Bar 能看到 5 小时 / 7 天用量并随会话更新；小角色能区分空闲、工作中、等待批准、完成四种状态。

### 阶段 3：配置化

- [ ] 新增 `~/.claude-touchbar/config.json`，hook 和 app 都从中读取按钮规则
- [ ] 安全底线写死在代码里，配置无法覆盖：高风险 / 未知风险永不显示一键批准
- [ ] 为安全底线补测试

验收：修改配置后无需重启即生效；底线规则有测试覆盖。

### 阶段 4：SwiftUI 设置窗口

- [ ] GUI 编辑 config.json
- [ ] Touch Bar 布局实时预览

### 阶段 5：开源分发

- [ ] Python hook 改写为 Swift CLI 并打包进 app，去掉对 `python3` 的依赖（无 Command Line Tools 的机器上 `/usr/bin/python3` 只是安装提示）
- [ ] app 内提供"安装 hook"，写入 `~/.claude/settings.json` 前需用户确认
- [ ] GitHub Releases + Homebrew cask
- [ ] LICENSE、英文 README
- [ ] 签名与公证（需 Apple Developer 账号；否则文档说明 `xattr -cr`）

### 新增：Claude 桌面 app 的"下一步"提问上 Touch Bar（2026-11-06 实测通过）

- [x] PreToolUse 记下 `mcp__ccd_turn__wrap_up` 的问题和按钮，Touch Bar 显示 `[问题] [选项] [选项] [On screen]`
- [x] `questions.jsonl` 记录每个问题的开始 / 结束
- [x] 实测发现：同步 Stop hook 等待期间屏幕上的提问框是隐藏的（桌面 app 要等同步 Stop hook 全部结束才显示）
- [x] 改为后台 `asyncRewake` Stop hook：回合立即结束，屏幕和 Touch Bar 同时显示提问；点 Touch Bar → 退出码 2 唤醒 Claude；在屏幕上回答 → 新回合的 `UserPromptSubmit` 撤掉 Touch Bar 上的问题；最多挂 5 分钟；Touch Bar app 没运行时跳过（pid 记在 `frontmost.json`）
- 依赖桌面 app 内部工具，app 更新可能失效；终端里不适用
- [x] 实测：asyncRewake 送来的回答被标注为"不是用户输入"，不能作为提交 / 推送等对外操作的同意。改为给 `git commit`、`git push`、`gh pr` 加 `ask` 规则，由权限请求（同样在 Touch Bar 上）把关：点一次答案 + 一次权限 `Yes`
- [x] 一次点击提交推送：不再先问"要不要提交推送"，直接执行合并的 `git commit … && git push`，由 `ask` 规则触发的权限请求作为唯一的提问；Touch Bar 上显示 `Commit & push` / `Commit` / `Push`。实测：点 `Yes` 一次完成提交推送；点 `No` 整条命令被拦下，只留下已暂存的文件
- [x] 修复：hook 等待时每 5 秒刷新 state，会把"已在屏幕上处理"的新状态覆盖回旧请求，导致 Touch Bar 残留按钮；现在发现 state 被新事件接管就立即停止等待、不再回写；但 "Claude needs your permission" 这类 Notification 不算新进展，不会覆盖仍在等待的请求（否则请求约 6 秒就会消失）
- [ ] 提交推送的权限请求在 Touch Bar 上显示成提问框样式（底层仍是权限请求）：`Commit & push? <提交标题>` + `提交并推送`（蓝）/ `先不提交` / `On screen`；只单独推送时为 `Push?` / `推送`；其他权限请求保持 `Yes / No / Review`。屏幕上的权限框是桌面 app 的标准样式，改不了
- 已知：在 Touch Bar 上回答"下一步"提问后，屏幕上的提问框要过几秒（Claude 被唤醒、新回合开始）才消失，桌面 app 的行为，无法从 hook 关闭
- [ ] 后续：同样的方式支持官方的 `AskUserQuestion`（PreToolUse + `updatedInput.answers`，终端和桌面都能用）

### 提前完成（原属阶段 5）

- [x] 后台常驻 + 开机自启：`scripts/install-launch-agent.sh` 安装 LaunchAgent（登录启动、崩溃重启），二进制放在 `~/Library/Application Support/`；app 单实例锁；退出时移除 Control Strip 项，避免进程被杀后留下点不动的旧按钮

### 后续候选

- [ ] 多 session 状态隔离

## 待决定

- 阶段 3 自定义范围：外观（文案 / 颜色 / 顺序）、策略（每个风险等级显示哪些按钮）、空闲时的额外按钮，先做哪几类
- 阶段 2：小角色只跟着状态动，还是也要纯装饰动画
- 提交推送的权限请求要不要改成提问框样式（见"下一步"提问一节），按钮文案用中文还是英文
- 是否安装 Xcode（目前只有 Command Line Tools + Swift 6.0.3）

## 风险

- 依赖私有 API：无法上 App Store，未来 macOS 更新可能失效
- 带 Touch Bar 的 Mac 已于 2022 年停产，受众较小

## 暂不做

- 解析完整终端 TUI
- 多 session 管理
- 键盘注入
- 绕过 Claude Code 原有权限机制
