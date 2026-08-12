---
last-reviewed: 2026-08-12
---

# 0008：采用 Beta 集成与标签发布分支模型

**日期：** 2026-08-11
**状态：** Accepted
**取代：** ADR-0002 中的 GitHub Flow、以 `main` 作为日常开发基线的部分

## 背景

项目需要把持续测试版本与正式版本明确隔离。`main` 不允许直接操作，日常开发变更需要先汇聚到 Beta 环境接受流水线验证；正式发布则需要一个显式、可审计且不会因普通分支更新而误触发的信号。项目 CI/CD 使用 Xcode Cloud，工作流和启动条件在 Xcode 或 App Store Connect 中管理，而不是存放在仓库内的 GitHub Actions 配置。

## 考虑的方案

1. **继续使用 `main` 为唯一长期分支**：流程简单，但 Beta 与正式发布共享同一基线和触发信号，无法满足 `main` 禁止日常操作的要求。
2. **采用长期 `beta` 集成分支与 `release*` 正式标签**：日常集成、稳定代码和正式发布信号清晰分离。
3. **采用完整 Gitflow 并增加 `develop`、`release/*` 分支**：隔离最细，但对当前个人维护规模引入不必要的长期分支和合并成本。

## 决策

采用带长期 `beta` 集成分支的发布模型：

1. `main` 是稳定分支，开启分支保护，不允许任何直接 push、强推或删除。
2. `beta` 是 GitHub 默认分支和日常集成分支，同样开启分支保护。所有 `feat/*`、`fix/*`、`refactor/*`、`docs/*`、`test/*`、`chore/*` 分支从最新 `beta` 创建，并通过 PR 合入 `beta`。
3. Xcode Cloud 的 Beta 工作流使用 Branch Changes 启动条件，精确监听 `beta`。`beta` 每次更新都触发该工作流，供持续集成和测试版本分发。
4. 需要对某个 `beta` 提交生成显式、可追溯的候选包时，可在该提交创建 `beta-<version>-<sequence>` 标签；Beta 工作流额外以 Tag Changes 只监听 `beta-*`。此标签不是正式发布信号，序号也不等于 Xcode Cloud Build Number。
5. 准备正式发布时，从 `beta` 向 `main` 发起发布 PR。合并并确认提交后，在该 `main` 提交上创建并推送以 `release` 开头的标签；建议格式为 `release-<version>`。
6. Xcode Cloud 的 Release 工作流使用 Tag Changes 启动条件，只响应 `release*` 标签。不得在功能分支、未合入 `main` 的 `beta` 提交或其他历史提交上创建正式发布标签。
7. PR 采用 squash merge，提交继续使用 Conventional Commits。
8. 工作流触发契约、环境变量诊断和人工核对步骤记录在 `docs/operations/xcode-cloud.md`；实际工作流设置以 Xcode Cloud 为准，变更设置时必须同步文档。

当前仓库为个人维护场景，分支保护要求必须通过 PR 且必须解决评审讨论，但暂不要求至少一位其他审批者，避免无人可审时阻塞发布。团队扩大后可单独提高审批人数。

## 后果

### 正面

- 日常集成不会直接改变稳定分支。
- Beta 与正式流水线各自拥有清晰、互不重叠的触发信号。
- 正式版本可以通过 `main` 提交和 `release*` 标签双重追溯。
- 分支模型与 Xcode Cloud 原生的 Branch Changes、Tag Changes 启动条件一一对应，无需维护重复的 GitHub Actions 流水线。

### 负面

- 正式发布增加一次 `beta` 到 `main` 的提升 PR。
- `beta` 可能长期领先 `main`，发布与热修复时必须注意基线选择。

### 中性

- `beta` 成为 GitHub 默认分支，使新 PR 默认以它为目标；`main` 仍是稳定发布分支。
- 分支保护暂不要求其他维护者审批；这项设置可随团队规模调整，不改变分支与流水线模型。
- Xcode Cloud 工作流配置不随 Git 仓库克隆；维护者需要在 Xcode 或 App Store Connect 中查看和修改实际配置。

### 热修复

正式版本的紧急修复从 `main` 创建 `fix/*` 分支，经验证后仍先 PR 到 `beta`。确认 `beta` 无其他尚不应发布的变更时，再按正常流程提升到 `main` 并创建新的 `release*` 标签；若 `beta` 含不可发布变更，应从修复分支分别向 `beta` 和 `main` 提 PR，不得直接 push。
