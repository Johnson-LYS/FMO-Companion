---
last-reviewed: 2026-08-04
---

# 项目简报

## 概览

FMO Companion 是服务于持证业余无线电爱好者的原生 iOS App。它把 iPhone 作为 FMO 盒子的局域网伴侣、GPS 来源、APRS 信息终端、远程控制器、QSO 日志工具和自建服务器运维入口。

项目坚持公开接口边界：使用官方 GEO WebSocket、FMO V4 APRS、官方 APRS 远控示例、用户导出的 QSO 文件及用户自建 HTTPS API，不逆向核心语音协议或设备私钥。

## 当前状态

- **阶段：** 0.2 可靠定位开发中
- **已完成：** 0.1 局域网闭环；0.2 已完成三种定位模式、后台位置事件、自动同步协调器、可取消退避、位置自动化 UI、App 生命周期恢复及官方 Web 入口
- **进行中：** 真实 iPhone + FMO 的后台、锁屏、离网恢复、停止及系统终止恢复闭环
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
| 2026-08-03 | 启动 0.1 开发，完成原生局域网连接首个可运行切片 | `docs/plans/0002-milestone-0.1-local-connection.md` |
| 2026-08-03 | 采用 Swift 6 完整严格并发检查 | `docs/adr/0004-swift-6-strict-concurrency.md` |
| 2026-08-03 | 真机修正 Bonjour 地址作用域问题，改为持久化 `fmo.local` 稳定身份 | `docs/architecture/modules/device-connectivity.md` |
| 2026-08-03 | 修正 SwiftUI 整行条目留白无法点击，并固化全宽命中规范 | `docs/design/ui-design-system.md` |
| 2026-08-03 | 完成 Wi-Fi、主机端口、HTTP 与 GEO WebSocket 四步实时连接诊断 | `docs/architecture/modules/device-connectivity.md` |
| 2026-08-03 | 补齐权限拒绝的系统设置恢复入口与异常断线状态收敛覆盖 | `docs/architecture/modules/device-connectivity.md` |
| 2026-08-04 | 修正发现覆盖手动设备、补齐设备移除，并区分首页会话与独立诊断结果 | `docs/architecture/modules/device-connectivity.md` |
| 2026-08-04 | 设备删除改为系统原生左滑，并固化为所有可删除列表的 UI 规范 | `docs/design/ui-design-system.md` |
| 2026-08-04 | Johnson iPhone 13 Pro + 真实 FMO 完成 0.1 全流程真机验收 | `docs/plans/0002-milestone-0.1-local-connection.md` |
| 2026-08-04 | 冻结 0.2 模式阈值、离网恢复与系统浏览器契约并启动开发 | `docs/plans/0005-milestone-0.2-reliable-location.md` |
| 2026-08-04 | 完成 0.2 定位策略、iOS 26 后台会话、授权映射、模式存储与工程配置 | `docs/architecture/modules/location-sync.md` |
| 2026-08-04 | 完成自动同步协调器、网络门控、离网恢复和可取消指数退避 | `docs/architecture/modules/location-sync.md` |
| 2026-08-04 | 接入位置自动化状态页、启动恢复、共享稳定端点与官方管理/QSO 系统浏览器入口 | `docs/plans/0005-milestone-0.2-reliable-location.md` |

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
- [ADR-0004：采用 Swift 6 严格并发](adr/0004-swift-6-strict-concurrency.md)

## 本轮开发入口

1. 阅读 `docs/plans/0003-product-roadmap.md` 的 0.2 范围。
2. 阅读 `docs/spec/product-spec.md` 的 SPEC-004、SPEC-005。
3. 继续遵循 `docs/design/ui-design-system.md` 与 `docs/design/prototype-implementation-guide.md`。
4. 按 `docs/plans/0005-milestone-0.2-reliable-location.md` 在真机完成后台、锁屏、离网恢复、停止和系统终止恢复测试。
