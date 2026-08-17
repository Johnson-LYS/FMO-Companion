# FMO Companion Agent Guide

This file is the repository entry point for AI-assisted development. `CLAUDE.md` points to this file so Codex, Claude Code, and other agents share one source of truth.

## Language Preferences

| Setting | Language |
|---|---|
| Conversation | 中文 |
| Documentation | 中文 |
| Code identifiers | English |
| Code comments | 中文或英文均可，但仅在解释“为什么”时添加 |

## Project Summary

FMO Companion is a native iOS companion app for FMO (NFM Over Internet) hardware. It uses only documented interfaces and user-authorized services:

- Bonjour/mDNS and the documented local GEO WebSocket API.
- The strictly allowlisted, user-authorized local read-only status API described by ADR-0005.
- The isolated, strictly allowlisted local server catalog and UID switching contract described by ADR-0010.
- The isolated, user-controlled local receive-audio contract described by ADR-0009, including audible background playback while the user leaves sound enabled.
- Public FMO V4 APRS frames and standard APRS-IS behavior.
- The documented APRS remote-control format.
- The user-authorized, strictly read-only local QSO list/detail contract fixed by ADR-0007, plus user-exported QSO archives when explicitly chosen.
- A separately authenticated HTTPS API for the user's own FMO server.

The app must not perform runtime packet sniffing or rely on firmware reverse engineering, private-key extraction, audio formats beyond ADR-0009's fixed user-confirmed receive-only PCM contract, or impersonating an FMO device. The ADR-0005 status client and ADR-0007 QSO client are limited to sanitized, typed, read-only behavior observed in the official UI; they must never expose generic management commands, secrets, write operations, backup/restore triggers, or `/audio`. ADR-0010 server switching must remain a separate client limited to device server lists, current-server readback, and switching to a previously listed UID; it must never expose generic commands or other device writes. ADR-0009 audio must remain a separate receive-only client; background execution is allowed only for audible playback explicitly enabled by the user, never as silent keepalive, and PCM must never be recorded, persisted, uploaded, transmitted, or logged.

## Documentation Map

All agents must use these paths. Update this table when documentation moves.

| Purpose | Path |
|---|---|
| Session entry point | `docs/project-brief.md` |
| Product requirements | `docs/spec/product-spec.md` |
| Technical requirements | `docs/spec/technical-spec.md` |
| Architecture overview | `docs/architecture/overview.md` |
| Module documentation | `docs/architecture/modules/` |
| UI design system | `docs/design/ui-design-system.md` |
| Prototype coverage matrix | `docs/design/prototype-coverage-matrix.md` |
| Prototype implementation guide | `docs/design/prototype-implementation-guide.md` |
| ADR index | `docs/adr/README.md` |
| Implementation plans | `docs/plans/` |
| FMO protocol references | `docs/references/` |
| Xcode Cloud workflows | `docs/operations/xcode-cloud.md` |
| Interactive HTML prototype | `prototype/` |
| Loom project skills | `.claude/skills/` |
| Loom project agents | `.claude/agents/` |
| Codex skill mirror | `.agents/skills` → `.claude/skills` |

## Session Start Protocol

At the beginning of a development session:

1. Read `AGENTS.md` and `docs/project-brief.md`.
2. Read only the specification, ADR, module document, and plan relevant to the task.
3. Run `bash .claude/scripts/drift-check-hook.sh` as a quick freshness check.
4. Inspect `git status --short --branch`; preserve unrelated user changes.
5. State any documentation drift or scope uncertainty, then continue unless it materially changes the requested outcome.

## Development Rules

- Target iOS 26 or later and use SwiftUI with Swift Concurrency.
- Prefer current iOS 26 APIs directly. Do not add availability branches or compatibility shims for older iOS releases unless the deployment policy is explicitly changed.
- Prefer Apple frameworks before adding dependencies: Network, CoreLocation, MapKit, CryptoKit, SwiftData, UserNotifications, WebKit, LocalAuthentication.
- Treat all network and location operations as asynchronous and cancellation-aware.
- Keep protocol parsing and cryptographic verification independent from UI code.
- Use dependency injection through protocols for network, location, clock, storage, and APRS transports.
- Never log APRS PASSCODEs, remote-control secrets, bearer tokens, precise location, or synchronized/exported QSO contents in production logs.
- Store secrets only in Keychain. Do not put secrets in source, UserDefaults, test fixtures, screenshots, or documentation.
- Do not weaken certificate, signature, replay-window, or CRL validation to make tests pass.
- Use localized user-facing strings; do not hard-code visible copy deep in service layers.
- When implementing UI or a workflow represented in `prototype/`, read `docs/design/ui-design-system.md`, `docs/design/prototype-coverage-matrix.md`, and `docs/design/prototype-implementation-guide.md`; preserve the confirmed navigation and interaction hierarchy while replacing every browser simulation with typed Swift state and real injected services.
- New behavior requires unit tests. User journeys or permissions behavior that cannot be unit tested should have focused UI/integration coverage and a documented manual check.
- Never claim background execution occurs at exact periodic intervals; iOS scheduling is system-controlled.

## Planned Source Layout

```text
FMOc/
├── App/
├── Features/
│   ├── Device/
│   ├── Location/
│   ├── APRS/
│   ├── RemoteControl/
│   ├── QSO/
│   ├── Server/
│   └── Settings/
├── Core/
│   ├── Networking/
│   ├── Persistence/
│   ├── Security/
│   └── Diagnostics/
├── Models/
└── Resources/
```

Do not create all directories preemptively. Add them as the first real type in each area is implemented, then update module documentation.

## Verification

For normal code changes, run the narrowest relevant tests first, then the full suite when risk warrants it. Use a generic destination for the baseline build:

```bash
xcodebuild \
  -project FMOc.xcodeproj \
  -scheme 'FMO 助手' \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  -derivedDataPath /tmp/FMOcDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Tests require a concrete installed simulator. Find an available device with `xcrun simctl list devices available`, then run:

```bash
xcodebuild \
  -project FMOc.xcodeproj \
  -scheme 'FMO 助手' \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -configuration Debug \
  -derivedDataPath /tmp/FMOcDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

If no compatible simulator runtime is installed, report the missing runtime instead of changing deployment targets to hide the issue.

## Documentation Workflow (Loom)

This repository was bootstrapped using the structure and project-local assets from [The-Last-Humans/loom](https://github.com/The-Last-Humans/loom). Loom is not a runtime dependency.

After a change:

1. Decide whether requirements, architecture, public module APIs, dependencies, security rules, or conventions changed.
2. If yes, update the corresponding document and its `last-reviewed` date in the same change.
3. Add an ADR for a consequential, hard-to-reverse decision; do not create ADRs for routine implementation details.
4. Update `docs/project-brief.md` at the end of a meaningful development session.
5. Run the `doc-drift-check` and `syncing-docs-with-code` workflows before a PR.

Loom templates mention the optional Superpowers plugin. If it is unavailable, use the host agent's native planning, testing, review, and delegation tools; missing Superpowers is not a blocker.

## Git Conventions

| Setting | Value |
|---|---|
| Branching model | Beta integration flow |
| Stable branch | `main`（受保护，仅接受来自 `beta` 的发布 PR） |
| Integration branch | `beta`（受保护、GitHub 默认分支、日常开发 PR 的唯一目标分支） |
| Branch naming | `<type>/<short-description>` |
| Commit format | Conventional Commits: `<type>: <description>` |
| Merge strategy | Squash merge |
| CI/CD platform | Xcode Cloud；工作流在 Xcode 或 App Store Connect 中管理 |
| Beta delivery | Xcode Cloud Beta 工作流监听精确分支 `beta`；候选包可由 `beta-*` 标签显式触发 |
| Production release | 将 `beta` 通过 PR 提升到 `main`，再推送 `release*` 标签，由 Xcode Cloud Release 工作流的 Tag Changes 触发 |

Branch prefixes: `feat/`, `fix/`, `refactor/`, `docs/`, `test/`, `chore/`.

- 不得直接向 `main` 或 `beta` push；不得绕过分支保护。所有日常开发分支从最新 `beta` 创建，并向 `beta` 提交 PR。
- `main` 只保存已正式发布或准备立即正式发布的稳定代码；只接受从 `beta` 发起的发布 PR。
- Beta 流水线是 Xcode Cloud 工作流，以 Branch Changes 精确监听 `beta`；正式流水线是独立的 Xcode Cloud 工作流，只以 Tag Changes 监听 `release*`。
- 需要显式生成可追溯 Beta 候选包时，在 `beta` 当前提交创建 `beta-<version>-<sequence>` 标签，例如 `beta-0.1.0-1`；Beta 工作流的 Tag Changes 只包含 `beta-*`。标签序号仅用于 Git 候选追踪，不代替 Xcode Cloud 构建号。
- 正式发布标签必须指向 `main` 上由 `beta` 提升而来的提交，建议采用 `release-<version>`，例如 `release-1.0.0`。
- Xcode Cloud 使用 `ci_scripts/ci_pre_xcodebuild.sh` 在 `analyze`、`archive`、`build` 与 `build-for-testing` 的 `xcodebuild` 紧前方将 `CI_BUILD_NUMBER` 写入工程，并校验 App 实际解析的 `CURRENT_PROJECT_VERSION`，确保关于页、构建产物与 App Store Connect 使用同一 Build。`test-without-building` 只复用先前构建产物且恢复环境可能没有源码，必须在访问本地化输入或工程前跳过。不得在 UI 中读取或展示 CI 环境变量。
- Xcode Cloud 工作流配置不存放在 GitHub Actions YAML 中。修改触发条件、构建动作、签名或分发设置时，应同步更新 `docs/operations/xcode-cloud.md`，且不得把密钥写入仓库。
- Do not push or open a PR unless the user asks.
- Keep commits atomic and do not mix unrelated user changes.
- Never commit signing credentials, provisioning profiles, private keys, APRS secrets, server tokens, or precise-location exports.

## Source-of-Truth Order

When information conflicts, use this order:

1. Current user request.
2. Accepted ADRs.
3. Product and technical specifications.
4. Architecture/module documentation.
5. Active implementation plan.
6. Existing code and tests.

If code intentionally departs from accepted documentation, update the documentation or record a superseding ADR in the same unit of work.
