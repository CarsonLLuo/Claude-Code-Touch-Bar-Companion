# Claude Code Touch Bar Companion

## 更新日期

2026-06-09

## 当前状态

MVP 核心链路已跑通。`PermissionRequest` hook 端到端可用，Touch Bar 显示权限摘要、风险分级按钮，用户点击后通过结构化 hook decision 回传 Claude Code。

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
- [ ] Stop 状态不显示未实现的 Continue / Stop action
- [ ] demo 可在 2 分钟内稳定复现

## 待完成

### P0

- [ ] 隐藏 `Stop` 事件的 Continue / Stop 按钮
  - 验收：Stop 只显示 `Claude done`，actions 为空

- [ ] 完成真实测试矩阵
  - `Read` → Yes / No
  - `Write/Create` → All edits
  - 项目内单文件 `rm` → Yes
  - `rm -rf` → Review / No
  - `python3 ...` → 短摘要

- [ ] 准备 2 分钟 demo checklist

### 后续候选

- [ ] 观察 BTT 1-2 秒刷新长期稳定性
- [ ] 考虑导出 BTT preset 方便新环境复现
- [ ] 多 session 状态隔离

## 暂不做

- 解析完整终端 TUI
- 多 session 管理
- 键盘注入
- 原生 Swift / AppKit helper
- 公开分发安装包
- 绕过 Claude Code 原有权限机制
