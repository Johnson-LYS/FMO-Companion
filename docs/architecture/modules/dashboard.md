---
last-reviewed: 2026-08-05
---

# 模块：Dashboard

## 目的

把 GEO、ADR-0005 本地只读状态与本地讲话事件聚合成首页和未来 ActivityKit 共用的非敏感设备状态快照。延迟、管理员与在线人数不进入 0.3 模型，也不会由原型 fixture 或替代来源填充。

## 公共接口

```swift
enum DashboardField<Value>: Codable, Equatable, Sendable {
    case available(DashboardObservation<Value>)
    case unknown
    case stale(DashboardObservation<Value>, staleAt: Date)
    case unsupported
    case rejected(reason: String)
}

struct DashboardObservation<Value>: Codable, Equatable, Sendable {
    let value: Value
    let source: DashboardFieldSource
    let observedAt: Date
    let confidence: DashboardConfidence
}

struct DashboardSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Date
    var geoLink: DashboardLinkState
    var localStatusLink: DashboardLinkState
    var localEventLink: DashboardLinkState
    // 呼号、服务器、过滤距离、网格、日志数、单一频率、讲话与近期活动。
}

actor DashboardStore {
    func beginConnection() -> DashboardSnapshot
    func recordGeoCoordinate(_ coordinate: GeoCoordinate) -> DashboardSnapshot
    func recordGeoDisconnection() -> DashboardSnapshot
    func recordLocalStatus(_ update: DashboardLocalStatusUpdate) -> DashboardSnapshot
    func recordLocalEvent(_ event: FmoLocalEvent) -> DashboardSnapshot
    func reset() -> DashboardSnapshot
}
```

`DashboardSnapshot` 是唯一规范快照。SwiftUI 与未来 Widget Extension 只消费投影，不自行解释 GEO、APRS 或设备状态协议。

## 内部结构

- `DashboardStore` 使用 Actor 隔离可变聚合状态，并通过 `DashboardDateProviding` 注入观测时钟。
- 新连接开始时创建空快照，避免不同 FMO 之间复用旧数据。
- GEO 坐标成功读取后只把六位 Maidenhead 写入 Dashboard；精确经纬度仍归 Device/Location 流程，不进入锁屏候选快照。
- GEO 断开后保留最后可信 Maidenhead 并转换为 `stale`；删除设备则完全重置快照。
- `MaidenheadLocator` 是无状态纯转换器，处理 WGS84 合法范围及 `90° / 180°` 闭区间边界。
- `FmoLocalStatusWebSocketClient` 在独立 `/ws` 连接上串行读取呼号、当前服务器、过滤距离、单一工作频率和 QSO 日志数；任何命令失败只留下对应字段 `unknown`。
- `FmoLocalEventWebSocketClient` 独立连接 `/events`。讲话空闲或断流立即清除当前讲话者；近期历史断流后只保留为 `stale`。
- 状态响应上限 256 KiB，事件帧上限 64 KiB；超限、超时或路由错位会关闭该会话，避免迟到响应污染下一条无请求 ID 的命令。
- 延迟、管理员呼号和在线/最大人数在 0.3 模型与投影中隐藏，不进入未来 ActivityKit payload。
- 首页投影采用已确认的三段式卡片：上部放大显示呼号，其下仅用定位与范围图标呈现 Maidenhead 和过滤距离；下部单一大胶囊把当前服务器与最新动态放在一起。卡片不显示 QSO 数、频率、分隔线、解释性标签或连接/断开操作，字段未知时直接省略而不使用示例值补位。

## 数据流

```text
FmoGeoClient.getCoordinate
FmoLocalStatusProviding ─┐
FmoLocalEventStreaming ──┼→ DashboardStore actor → DashboardSnapshot
validated GeoCoordinate ─┘             └→ MaidenheadLocator
→ DeviceDashboardSummaryView
→ future Live Activity projection
```

## 依赖与边界

- Foundation：时间与 Codable 快照。
- SwiftUI：仅 `DeviceDashboardSummaryView` 投影视图。
- Device 的 `GeoCoordinate`：已经完成范围校验的输入值。
- Dashboard 不持有 WebSocket、Bonjour、Core Location、APRS 或存储客户端。
- `/ws` 状态客户端与 `/events` 事件流位于 Device 网络层，通过类型化值注入 Dashboard；Dashboard 不能发送管理命令或接触原始帧。
- HTML、Preview 与测试 fixture 不进入 Release 依赖组合；生产 App 只由真实服务更新快照。

## 关键文件

- `FMOc/Features/Dashboard/DashboardSnapshot.swift`
- `FMOc/Features/Dashboard/DashboardStore.swift`
- `FMOc/Features/Dashboard/MaidenheadLocator.swift`
- `FMOc/Features/Dashboard/DeviceDashboardSummaryView.swift`
- `FMOc/Features/Device/DeviceHomeModel.swift`
- `FMOc/Features/Device/FmoLocalStatusProtocol.swift`
- `FMOc/Features/Device/FmoLocalStatusWebSocketClient.swift`
- `FMOc/Features/Device/FmoLocalEventProtocol.swift`
- `FMOc/Features/Device/FmoLocalEventWebSocketClient.swift`

## 测试

- 已知坐标与 WGS84 边界的六位 Maidenhead 向量。
- 空快照的三条链路独立且字段为 `unknown`。
- GEO、状态和事件的连接、断开转过期及切换设备隔离。
- 快照 Codable 往返与 4 KB 基础体积警戒线。
- 协议测试覆盖五个只读请求、PASSCODE/写命令排除、过滤枚举与讲话/历史 schema。
- 客户端测试覆盖 `/events` 固定路径、帧大小上限与异常后会话失效。
- `DeviceHomeModel` 把 GEO 和本地只读字段投影为 Dashboard 状态。
- Debug-only UI 场景验证图标优先的完整首页投影、启动发现后的首台自动连接，以及正式依赖组合不出现原型 fixture。
