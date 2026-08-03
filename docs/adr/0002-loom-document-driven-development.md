---
last-reviewed: 2026-08-03
---

# 0002：采用 Loom 文档驱动的 Agent 工作流

**日期：** 2026-08-03
**状态：** Accepted

## 背景

项目将由用户与多个 AI Agent 长期协作。聊天上下文不会天然跨会话保存，而 FMO 协议、安全边界、iOS 后台限制和服务器依赖需要持续保持一致。

## 考虑的方案

1. **只维护 README**：简单，但难以承载需求、ADR、模块边界与实施计划。
2. **采用 Loom 的仓库内知识结构**：文档、项目技能、审计 Agent 和漂移检查全部随代码版本化。
3. **依赖外部知识库**：适合个人整理，但克隆代码后无法自动获得同一上下文。

## 决策

采用 The-Last-Humans/loom 的 `docs/`、项目技能、项目 Agent 与文档漂移工作流，并增加 `AGENTS.md` 作为跨 Agent 入口。`CLAUDE.md` 和 `.agents/skills` 使用链接复用同一份内容，避免双份规则漂移。

文档使用中文，代码标识符使用英文。Git 默认采用 GitHub Flow、`main`、Conventional Commits 与 squash merge。

## 后果

### 正面

- 新 Agent 可以先读项目简报和相关文档，而不必扫描整个代码库。
- 需求、架构、实施和代码可以在同一 Git 变更中演进。
- `last-reviewed` 与漂移检查能较早暴露文档陈旧问题。

### 负面

- 每次架构或接口变化需要额外维护文档。
- Loom 原模板偏向 Claude Code，必须通过 `AGENTS.md` 和 `.agents/skills` 兼容 Codex。
- 原始 Hook 使用 GNU 工具，项目需要维护 macOS 兼容版本。

### 中性

- Loom bootstrap 后不再是运行时依赖；生成资产直接属于本仓库。
