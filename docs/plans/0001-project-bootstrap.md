---
last-reviewed: 2026-08-03
status: completed
---

# 计划 0001：项目基础环境

## 目标

把 Xcode 初始模板整理为可由 Codex、Claude Code 和人工开发者共同维护的文档驱动仓库，并建立可验证的 iOS 项目基线。

## 工作项

- [x] 盘点 Xcode Target、SwiftUI 入口和测试 Target。
- [x] 创建 `AGENTS.md` 并通过 `CLAUDE.md` 共用同一入口。
- [x] 使用 Loom 默认文档地图创建 brief、spec、architecture、ADR 和 plans。
- [x] 安装 Loom 的 9 个项目技能、2 个文档 Agent 和 SessionStart 漂移 Hook。
- [x] 为 Codex 提供 `.agents/skills` 镜像入口。
- [x] 将漂移 Hook 改为兼容 macOS 与 GNU/Linux。
- [x] 添加 README、`.gitignore`、`.editorconfig` 和第三方许可说明。
- [x] 把 FMO iOS 功能规划与公开能力边界写入仓库。
- [x] 将最低部署版本从 Xcode 模板默认值调整为 iOS 17.0。
- [x] 将 App 显示名称设为 `FMO Companion`，保留当前工程/Target 名 `FMOc`。
- [x] 初始化 `main` Git 仓库。
- [x] 完成一次无签名 Simulator 构建验证。
- [x] 在 iOS 18.6 Simulator 上完成初始单元测试与 UI 测试。

## 验收

- 新会话只需阅读 `AGENTS.md` 与 `docs/project-brief.md` 即可定位当前目标。
- `bash .claude/scripts/drift-check-hook.sh` 在当前文档状态下静默成功。
- `git status` 不追踪 `.DS_Store`、`xcuserdata` 和 `*.xcuserstate`。
- Xcode 工程能在可用的 iOS Simulator SDK 上构建并通过初始测试。

## 备注

项目为绿色项目，尚无产品代码和历史 Git 约定。本计划采用 Loom 推荐默认值：中文文档、GitHub Flow、`main`、Conventional Commits、Squash Merge。需要调整时更新 `AGENTS.md` 并视影响补充 ADR。
