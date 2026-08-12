---
last-reviewed: 2026-08-12
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
| Beta | Branch Changes；Tag Changes | 精确匹配 `beta`；仅包含 `beta-*` | `refs/heads/beta` 或 `refs/tags/beta-<version>-<sequence>` | 持续集成与显式 Beta 候选构建/分发 |
| Release | Tag Changes | 包含 `release*`，排除其他标签 | `refs/tags/release*` | 正式版本构建/分发 |

工作流在 Xcode Cloud 中可以使用其他显示名称，但启动条件必须符合上表。不要给 Release 工作流增加普通分支变更条件，否则日常提交可能误触发正式发布。

## 分支与发布流程

### 日常开发与 Beta

1. 从最新 `beta` 创建符合 `<type>/<short-description>` 的开发分支。
2. 向 `beta` 提交 PR；不得直接 push 到 `beta`。
3. PR 通过后 squash merge。
4. 合并产生的 `beta` 分支变更应由 Xcode Cloud Beta 工作流自动捕获。
5. 在 Xcode 或 App Store Connect 中确认构建所用 Git 引用为 `refs/heads/beta`。

需要生成可追溯的 Beta 候选包时，在已通过验收的 `beta` 当前提交创建并推送 `beta-<version>-<sequence>` 标签，例如 `beta-0.1.0-1`。该序号只区分同一营销版本的 Git 候选，不应手工猜测或复制 Xcode Cloud Build Number。推送后确认 Beta 工作流使用 `refs/tags/<标签名>`；不得把 `beta-*` 配入 Release 工作流。

## 构建号同步

关于页从最终 App Bundle 的 `CFBundleShortVersionString` 与 `CFBundleVersion` 动态读取版本。仓库的 `ci_scripts/ci_pre_xcodebuild.sh` 在每个 Xcode Cloud Action 调用 `xcodebuild` 前执行，并使用 Apple 预定义的正整数 `CI_BUILD_NUMBER` 调用 `agvtool new-version -all`。脚本随后读取 App 与 Live Activity 的 Debug、Release Build Settings，只有实际解析出的 `CURRENT_PROJECT_VERSION` 全部与云端构建号一致才允许 Action 继续。因此归档、关于页和 App Store Connect 展示同一个 Build；本地构建不在脚本中改号，继续使用工程的 `CURRENT_PROJECT_VERSION`。

脚本必须满足以下约束：

- 只在 `CI_XCODE_CLOUD=TRUE` 时修改临时检出的工程。
- 缺少或收到非法 `CI_BUILD_NUMBER` 时失败关闭，不能静默产出错误版本。
- 必须紧邻 `xcodebuild` 执行并验证 Xcode 实际解析的 App Build Settings；只验证项目文件写入成功不算完成。
- App 与同包扩展使用相同构建号；不把 CI 变量写入源码、用户默认值或可见调试字段。
- Xcode Cloud 构建日志可记录最终构建号，但不得输出密钥、签名或其他 Secret。

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
| Tag Changes | `CI_TAG` | `beta-0.1.0-1` 或 `release-1.0.0` |
| Branch Changes / Tag Changes | `CI_GIT_REF` | `refs/heads/beta`、`refs/tags/beta-0.1.0-1` 或 `refs/tags/release-1.0.0` |
| Xcode Cloud 每次构建 | `CI_BUILD_NUMBER` | 正整数，例如 `42`；写入归档 `CFBundleVersion` |

若 Beta 未自动启动，依次检查 Xcode Cloud 工作流是否启用、Branch Changes 是否精确包含 `beta`、Tag Changes 是否只包含 `beta-*`、SCM 连接是否仍有效，以及候选标签是否指向 `beta` 当前提交。若 Release 未自动启动，检查 Tag Changes 是否包含 `release*`、标签是否已推送到远端，以及标签指向是否为 `main` 的发布提交。

## 变更控制

- 分支保护由 GitHub 管理；Xcode Cloud 只负责构建和分发，不能替代 PR 保护。
- 工作流的构建动作、测试矩阵、签名与分发目标仍以 Xcode Cloud 实际配置为准，本文件不虚构未核实的动作。
- 修改启动条件或正式分发行为属于发布流程变更，必须同步更新 `AGENTS.md`、ADR-0008 与本文件；若改变分支模型或正式发布信号，应新增取代 ADR。
- Secret 只存放在 Xcode Cloud 的加密环境变量或 Apple 签名系统中，不得写入代码、文档或构建日志。
