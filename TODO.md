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
- [ ] 完成真实测试矩阵（不安装 BTT）
  - 测试/demo 模式下 `Read` → Yes / No
  - `Write/Create` → All edits
  - 项目内单文件 `rm` → Yes
  - `rm -rf` → Review on screen / No
  - `python3 ...` → 短摘要
- [ ] 准备 2 分钟 demo checklist

验收：卸载 BTT 后测试矩阵全部通过，demo 可稳定复现。

### 阶段 2：配置化

- [ ] 新增 `~/.claude-touchbar/config.json`，hook 和 app 都从中读取按钮规则
- [ ] 安全底线写死在代码里，配置无法覆盖：高风险 / 未知风险永不显示一键批准
- [ ] 为安全底线补测试

验收：修改配置后无需重启即生效；底线规则有测试覆盖。

### 阶段 3：SwiftUI 设置窗口

- [ ] GUI 编辑 config.json
- [ ] Touch Bar 布局实时预览

### 阶段 4：开源分发

- [ ] Python hook 改写为 Swift CLI 并打包进 app，去掉对 `python3` 的依赖（无 Command Line Tools 的机器上 `/usr/bin/python3` 只是安装提示）
- [ ] app 内提供"安装 hook"，写入 `~/.claude/settings.json` 前需用户确认
- [ ] GitHub Releases + Homebrew cask
- [ ] LICENSE、英文 README
- [ ] 签名与公证（需 Apple Developer 账号；否则文档说明 `xattr -cr`）

### 后续候选

- [ ] 多 session 状态隔离

## 待决定

- 阶段 2 自定义范围：外观（文案 / 颜色 / 顺序）、策略（每个风险等级显示哪些按钮）、空闲时的额外按钮，先做哪几类
- 是否安装 Xcode（目前只有 Command Line Tools + Swift 6.0.3）

## 风险

- 依赖私有 API：无法上 App Store，未来 macOS 更新可能失效
- 带 Touch Bar 的 Mac 已于 2022 年停产，受众较小

## 暂不做

- 解析完整终端 TUI
- 多 session 管理
- 键盘注入
- 绕过 Claude Code 原有权限机制
