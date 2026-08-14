---
last-reviewed: 2026-08-14
---

# 架构决策记录

| 编号 | 标题 | 状态 | 日期 |
|---|---|---|---|
| 0001 | [原生 iOS 与公开协议边界](0001-native-ios-public-protocol-boundary.md) | Accepted | 2026-08-03 |
| 0002 | [采用 Loom 文档驱动的 Agent 工作流](0002-loom-document-driven-development.md) | Accepted（Git 分支部分由 0008 取代） | 2026-08-03 |
| 0003 | [最低部署版本采用 iOS 26](0003-ios-26-minimum-deployment.md) | Accepted | 2026-08-03 |
| 0004 | [采用 Swift 6 严格并发](0004-swift-6-strict-concurrency.md) | Accepted | 2026-08-03 |
| 0005 | [采用用户授权的本地只读状态接口](0005-user-authorized-local-read-only-status.md) | Accepted | 2026-08-05 |
| 0006 | [隔离 APRS 只读与写会话](0006-isolated-aprs-write-session.md) | Accepted | 2026-08-07 |
| 0007 | [采用 FMO 本地只读 QSO 自动同步](0007-local-read-only-qso-sync.md) | Accepted | 2026-08-08 |
| 0008 | [采用 Beta 集成与标签发布分支模型](0008-beta-integration-release-flow.md) | Accepted | 2026-08-11 |
| 0009 | [采用用户授权的本地只接收 PCM 音频](0009-user-authorized-local-receive-audio.md) | Accepted | 2026-08-11 |
| 0010 | [采用用户授权的本地服务器切换](0010-user-authorized-local-server-switching.md) | Accepted | 2026-08-14 |

## 规则

ADR 记录影响范围广、难以轻易撤销的决策及其原因。已接受 ADR 不直接改写结论；需要改变时创建新的 ADR 并将旧记录标记为被取代。
