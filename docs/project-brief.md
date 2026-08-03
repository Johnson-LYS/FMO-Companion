---
last-reviewed: 2026-08-03
---

# 项目简报

## 概览

FMO Companion 是服务于持证业余无线电爱好者的原生 iOS App。它把 iPhone 作为 FMO 盒子的局域网伴侣、GPS 来源、APRS 信息终端、远程控制器、QSO 日志工具和自建服务器运维入口。

项目坚持公开接口边界：使用官方 GEO WebSocket、FMO V4 APRS、官方 APRS 远控示例、用户导出的 QSO 文件及用户自建 HTTPS API，不逆向核心语音协议或设备私钥。

## 当前状态

- **阶段：** 0.1 局域网闭环准备就绪，交互原型与 UI 设计基线已完成
- **正在进行：** 尚未开始产品代码；HTML 原型已覆盖 SPEC-001 至 SPEC-013 的代表性流程和全路线图信息架构
- **下一步：** 评审 `prototype/` 与 UI 设计方案后，实施 0.1：发现 FMO、连接 `/ws`、读取与写入坐标
- **首要验收设备：** 普通 Wi-Fi 或便携路由器中的真实 iPhone + FMO 盒子

## 最近变更

| 日期 | 变更 | 参考 |
|---|---|---|
| 2026-08-03 | 创建 Xcode SwiftUI 工程 | `FMOc.xcodeproj` |
| 2026-08-03 | 使用 Loom 结构初始化文档与 Agent 环境 | `docs/plans/0001-project-bootstrap.md` |
| 2026-08-03 | 将研究阶段的功能规划写入仓库 | `docs/plans/0002-milestone-0.1-local-connection.md` |
| 2026-08-03 | 通过初始单元测试与 UI 测试 | `docs/plans/0001-project-bootstrap.md` |
| 2026-08-03 | 将最低部署版本提高到 iOS 26.0，不维护旧系统兼容分支 | `docs/adr/0003-ios-26-minimum-deployment.md` |
| 2026-08-03 | 完成交互式 HTML 原型与 `#FF8800` UI 设计基线 | `docs/plans/0004-interactive-prototype-and-ui-design.md` |
| 2026-08-03 | 将原型扩展到全部规划规格并建立覆盖矩阵 | `docs/design/prototype-coverage-matrix.md` |
| 2026-08-03 | 将用户导航重构为四标签并重新归类功能 | `docs/design/ui-design-system.md` |
| 2026-08-03 | 移除可见评审层并新增面向 AI 的原型实现指南 | `docs/design/prototype-implementation-guide.md` |

## 领域术语

| 术语 | 定义 |
|---|---|
| FMO | NFM Over Internet；通过互联网连接的模拟窄带调频通联系统及硬件节点 |
| FMO 盒子 | 持有设备身份、负责发现、鉴权和语音处理的硬件终端 |
| GEO 接口 | 盒子在局域网开放的坐标读写 WebSocket 接口 |
| APRS-IS | APRS 互联网骨干；FMO 用于节点发现、事件和远程消息 |
| SAS | FMO Server Authorizer Service；为 MQTT Broker 提供证书鉴权与 ACL |
| STATION | FMO V4 中用于广播服务器地址、端口、覆盖范围和在线人数的报文 |
| CERT blob | FMO V4 报文携带的 CBOR 用户证书容器 |
| QSO | 两个业余无线电台之间的一次通联记录 |

## 核心业务规则

- 使用者必须自行具备合规的呼号、证书与 APRS 凭据；App 不代替资质认证。
- 设备私钥不得离开 FMO 盒子，App 不提取、不备份、不模拟。
- APRS PASSCODE 和远控 SECRET 只保存在 Keychain，不进入日志或云端同步。
- `VOCAL` 代表语音活跃事件，不等于语音内容。
- iOS 后台定位不能承诺固定分钟级调度，只能基于系统位置更新做节流。
- 未公开 API 的盒子设置通过官方 `fmo.local` Web UI 打开，不使用 DOM 注入或抓包模拟。
- FMO 连接 iPhone 自身个人热点的反向访问能力必须实机验证，在验证前不作为保证场景。

## 关键决策

- [ADR-0001：原生 iOS 与公开协议边界](adr/0001-native-ios-public-protocol-boundary.md)
- [ADR-0002：采用 Loom 文档驱动的 Agent 工作流](adr/0002-loom-document-driven-development.md)
- [ADR-0003：最低部署版本采用 iOS 26](adr/0003-ios-26-minimum-deployment.md)

## 本轮开发入口

1. 评审 `prototype/` 与 `docs/design/ui-design-system.md`，确认正式 UI 方向；实现时同时读取 `docs/design/prototype-implementation-guide.md`。
2. 阅读 `docs/spec/product-spec.md` 中 SPEC-001 至 SPEC-004。
3. 阅读 `docs/architecture/modules/device-connectivity.md`。
4. 执行 `docs/plans/0002-milestone-0.1-local-connection.md`。
