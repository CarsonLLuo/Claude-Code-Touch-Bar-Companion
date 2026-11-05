# Claude Code Touch Bar Companion

## 更新日期

2026-11-05

## 当前状态

MVP 核心链路已跑通。`PermissionRequest` hook 端到端可用，Touch Bar 显示权限摘要、风险分级按钮，用户点击后通过结构化 hook decision 回传 Claude Code。

BTT 试用已到期，目前没有可用的 Touch Bar 渲染层。方向调整为：开源的原生 Swift 菜单栏 app，替代 BTT 并提供 GUI 自定义按钮。

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

- [ ] 用量显示（会话 5 小时 / 周）
  - 数据来源：官方 status line stdin JSON 的 `rate_limits.five_hour` / `rate_limits.seven_day`（`used_percentage`、`resets_at`），可附带 `context_window.used_percentage`、`cost.total_cost_usd`；不用未公开的 OAuth 用量接口
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
  - 待实测：Control Strip 能放多宽；放不下分段电池就退回只显示数字的简单电池
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

### 后续候选

- [ ] 多 session 状态隔离

## 待决定

- 阶段 3 自定义范围：外观（文案 / 颜色 / 顺序）、策略（每个风险等级显示哪些按钮）、空闲时的额外按钮，先做哪几类
- 阶段 2：小角色只跟着状态动，还是也要纯装饰动画
- 是否安装 Xcode（目前只有 Command Line Tools + Swift 6.0.3）

## 风险

- 依赖私有 API：无法上 App Store，未来 macOS 更新可能失效
- 带 Touch Bar 的 Mac 已于 2022 年停产，受众较小

## 暂不做

- 解析完整终端 TUI
- 多 session 管理
- 键盘注入
- 绕过 Claude Code 原有权限机制
