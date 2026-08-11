---
last-reviewed: 2026-08-11
---

# Xcode Cloud 工作流

## 目的

本项目使用 Xcode Cloud 执行 Beta 与正式发布流水线。Xcode Cloud 工作流配置由 Xcode 或 App Store Connect 托管，仓库不维护等价的 GitHub Actions YAML；本文件记录必须保持稳定的触发契约和核对步骤。

Apple 官方说明 Xcode Cloud 可以按分支变更、PR 变更、标签变更或计划任务启动工作流，工作流可在 Xcode 或 App Store Connect 中维护：

- [Xcode Cloud workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference)
- [Configuring start conditions](https://developer.apple.com/documentation/xcode/configuring-start-conditions)
- [Environment variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference)

## 工作流触发契约

| 工作流 | Xcode Cloud 启动条件 | 匹配范围 | Git 来源 | 用途 |
|---|---|---|---|---|
| Beta | Branch Changes | 精确匹配 `beta` | `refs/heads/beta` | 持续集成与 Beta 版本构建/分发 |
| Release | Tag Changes | 包含 `release*`，排除其他标签 | `refs/tags/release*` | 正式版本构建/分发 |

工作流在 Xcode Cloud 中可以使用其他显示名称，但启动条件必须符合上表。不要给 Release 工作流增加普通分支变更条件，否则日常提交可能误触发正式发布。

## 分支与发布流程

### 日常开发与 Beta

1. 从最新 `beta` 创建符合 `<type>/<short-description>` 的开发分支。
2. 向 `beta` 提交 PR；不得直接 push 到 `beta`。
3. PR 通过后 squash merge。
4. 合并产生的 `beta` 分支变更应由 Xcode Cloud Beta 工作流自动捕获。
5. 在 Xcode 或 App Store Connect 中确认构建所用 Git 引用为 `refs/heads/beta`。

### 正式发布

1. 确认准备发布的 `beta` 提交已通过 Beta 工作流和发布验收。
2. 从 `beta` 向 `main` 创建发布 PR 并合并；不得直接操作 `main`。
3. 确认本地 `main` 与 `origin/main` 同步，并确认目标提交确实来自本次提升。
4. 在该 `main` 提交创建以 `release` 开头的标签；建议格式为 `release-<version>`，例如 `release-1.0.0`。
5. 推送标签后，在 Xcode 或 App Store Connect 中确认 Release 工作流使用 `refs/tags/<标签名>` 构建。

正式标签一旦推送可能触发分发，不得用真实 `release*` 标签测试触发条件。需要验证配置时，应使用 Xcode Cloud 的手动构建能力或由维护者在 App Store Connect 中检查启动条件。

## 诊断

Xcode Cloud 在不同启动条件下提供以下环境变量，可用于构建日志或自定义脚本诊断，但不得输出密钥或签名材料：

| 条件 | 环境变量 | 期望值示例 |
|---|---|---|
| Branch Changes | `CI_BRANCH` | `beta` |
| Tag Changes | `CI_TAG` | `release-1.0.0` |
| Branch Changes / Tag Changes | `CI_GIT_REF` | `refs/heads/beta` 或 `refs/tags/release-1.0.0` |

若 Beta 未自动启动，依次检查 Xcode Cloud 工作流是否启用、Branch Changes 是否精确包含 `beta`、SCM 连接是否仍有效。若 Release 未自动启动，检查 Tag Changes 是否包含 `release*`、标签是否已推送到远端，以及标签指向是否为 `main` 的发布提交。

## 变更控制

- 分支保护由 GitHub 管理；Xcode Cloud 只负责构建和分发，不能替代 PR 保护。
- 工作流的构建动作、测试矩阵、签名与分发目标仍以 Xcode Cloud 实际配置为准，本文件不虚构未核实的动作。
- 修改启动条件或正式分发行为属于发布流程变更，必须同步更新 `AGENTS.md`、ADR-0008 与本文件；若改变分支模型或正式发布信号，应新增取代 ADR。
- Secret 只存放在 Xcode Cloud 的加密环境变量或 Apple 签名系统中，不得写入代码、文档或构建日志。
