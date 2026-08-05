---
last-reviewed: 2026-08-04
---

# 模块：Dashboard

## 目的

把多个可信数据源聚合成首页与未来 ActivityKit 共用的非敏感设备状态快照。当前只接入公开 GEO 会话与由设备坐标派生的六位 Maidenhead；尚无正式接口的设备内部字段保留类型位置，但不会进入 `available`，也不会由原型 fixture 或替代来源填充。

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
    // 最终仪表盘字段；无正式来源者保持 unsupported。
}

actor DashboardStore {
    func beginConnection() -> DashboardSnapshot
    func recordGeoCoordinate(_ coordinate: GeoCoordinate) -> DashboardSnapshot
    func recordGeoDisconnection() -> DashboardSnapshot
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
- 当前服务器、过滤距离、实时 QSO、TX/RX、盒子到服务器延迟、管理员、在线人数和事件保持 `unsupported`。未来 Provider 必须先有公开接口契约，再以独立来源更新对应字段。

## 数据流

```text
FmoGeoClient.getCoordinate
→ validated GeoCoordinate
→ DashboardStore actor
→ MaidenheadLocator
→ DashboardSnapshot.maidenhead
→ DeviceDashboardSummaryView
→ future Live Activity projection
```

## 依赖与边界

- Foundation：时间与 Codable 快照。
- SwiftUI：仅 `DeviceDashboardSummaryView` 投影视图。
- Device 的 `GeoCoordinate`：已经完成范围校验的输入值。
- Dashboard 不持有 WebSocket、Bonjour、Core Location、APRS 或存储客户端。
- HTML、Preview 与测试 fixture 不进入 Release 依赖组合；生产 App 只由真实服务更新快照。

## 关键文件

- `FMOc/Features/Dashboard/DashboardSnapshot.swift`
- `FMOc/Features/Dashboard/DashboardStore.swift`
- `FMOc/Features/Dashboard/MaidenheadLocator.swift`
- `FMOc/Features/Dashboard/DeviceDashboardSummaryView.swift`
- `FMOc/Features/Device/DeviceHomeModel.swift`

## 测试

- 已知坐标与 WGS84 边界的六位 Maidenhead 向量。
- 空快照的延期字段保持 `unsupported`。
- GEO 连接、断开转过期及切换设备隔离。
- 快照 Codable 往返与 4 KB 基础体积警戒线。
- `DeviceHomeModel` 把真实 GEO 读取投影为 Dashboard 状态。
- Debug-only UI 场景验证首页显示派生网格，且不出现原型呼号或服务器 fixture。
