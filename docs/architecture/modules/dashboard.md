---
last-reviewed: 2026-08-11
---

# 模块：Dashboard

## 目的

把 GEO、ADR-0005 本地只读状态与本地讲话事件聚合成首页使用的非敏感设备状态快照。延迟、管理员与在线人数不进入 0.3 模型，也不会由原型 fixture 或替代来源填充。ActivityKit 相关类型与扩展当前仅为后续 checkpoint，不提供 0.3 用户入口或完成度。

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

struct FmoDashboardActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        // 连接状态、可选呼号、服务器、可选 Maidenhead、单一动态与更新时间。
    }
}

protocol DashboardLiveActivityClient: Sendable {
    func start(_ payload: DashboardLiveActivityPayload) async throws
    func update(_ payload: DashboardLiveActivityPayload) async -> Bool
    func end(_ payload: DashboardLiveActivityPayload) async
}
```

`DashboardSnapshot` 是唯一规范快照。SwiftUI 与 Widget Extension 只消费投影，不自行解释 GEO、APRS 或设备状态协议。

## 内部结构

- `DashboardStore` 使用 Actor 隔离可变聚合状态，并通过 `DashboardDateProviding` 注入观测时钟。
- 新连接开始时创建空快照，避免不同 FMO 之间复用旧数据。
- GEO 坐标成功读取后只把六位 Maidenhead 写入 Dashboard；精确经纬度仍归 Device/Location 流程，不进入锁屏候选快照。
- GEO 断开后保留最后可信 Maidenhead 并转换为 `stale`；删除设备则完全重置快照。
- `MaidenheadLocator` 是无状态纯转换器，处理 WGS84 合法范围及 `90° / 180°` 闭区间边界。
- `FmoLocalStatusWebSocketClient` 在独立 `/ws` 连接上串行读取呼号、当前服务器、过滤距离、单一工作频率和 QSO 日志数；任何命令失败只留下对应字段 `unknown`。
- `FmoLocalEventWebSocketClient` 独立连接 `/events`。讲话空闲或断流立即清除当前讲话者；近期历史断流后只保留为 `stale`。
- 状态响应上限 256 KiB，事件帧上限 64 KiB；超限、超时或路由错位会关闭该会话，避免迟到响应污染下一条无请求 ID 的命令。
- 延迟、管理员呼号和在线/最大人数在 0.3 模型与投影中隐藏。
- 首页投影采用已确认的三段式深色卡片：上部以显式白色放大显示呼号，同一行右侧只放打开设备选择 Sheet 的单行当前设备按钮（绿点、设备名、下箭头；“已连接”仅作为辅助功能值）；其下用小于数值字号的固定尺寸定位/范围图标呈现 Maidenhead 和过滤距离；下部单一大胶囊把当前服务器与最新动态放在一起。动态以规范化呼号作为整行切换身份：说话人变化时纵向替换；同一说话人由讲话转为最近活动时，只在固定槽位内替换图标并把呼号过渡为灰阶。相对时间由系统时间视图刷新。卡片不显示 QSO 数、频率、分隔线、解释性标签或断开操作，字段未知时直接省略而不使用示例值补位。
- ActivityKit 投影、状态机、客户端与独立 Widget Extension target 已形成可编译的探索 checkpoint；主 App target 不依赖、不嵌入该扩展，也不声明实时活动能力。为维持 checkpoint 的编译与单元测试，支持类型仍随主模块编译，但不进入 `AppComposition`，不会读取、创建或恢复活动。0.3 App 不展示入口、不启动活动，后续恢复前须重新经过文档与原型评审并显式恢复 Release composition。

## 数据流

```text
FmoGeoClient.getCoordinate
FmoLocalStatusProviding ─┐
FmoLocalEventStreaming ──┼→ DashboardStore actor → DashboardSnapshot
validated GeoCoordinate ─┘             └→ MaidenheadLocator
→ DeviceDashboardSummaryView
```

## 依赖与边界

- Foundation：时间与 Codable 快照。
- SwiftUI：0.3 只交付 `DeviceDashboardSummaryView`；实时活动管理页隐藏。
- ActivityKit：checkpoint 支持类型仍在主模块编译，但不进入 0.3 运行时组合；WidgetKit 只属于未嵌入的独立扩展 target。
- Device 的 `GeoCoordinate`：已经完成范围校验的输入值。
- Dashboard 不持有 WebSocket、Bonjour、Core Location、APRS 或存储客户端。
- `/ws` 状态客户端与 `/events` 事件流位于 Device 网络层，通过类型化值注入 Dashboard；Dashboard 不能发送管理命令或接触原始帧。
- HTML、Preview 与测试 fixture 不进入 Release 依赖组合；生产 App 只由真实服务更新快照。

## 关键文件

- `FMOc/Features/Dashboard/DashboardSnapshot.swift`
- `FMOc/Features/Dashboard/DashboardStore.swift`
- `FMOc/Features/Dashboard/MaidenheadLocator.swift`
- `FMOc/Features/Dashboard/DeviceDashboardSummaryView.swift`
- `FMOc/Features/Dashboard/FmoDashboardActivityAttributes.swift`
- `FMOc/Features/Dashboard/DashboardLiveActivityProjection.swift`
- `FMOc/Features/Dashboard/DashboardLiveActivityClient.swift`
- `FMOc/Features/Dashboard/DashboardLiveActivityModel.swift`
- `FMOc/Features/Dashboard/DashboardLiveActivityView.swift`
- `FMOcLiveActivity/FmoDashboardLiveActivityWidget.swift`
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
- Debug-only UI 场景验证图标优先的完整首页投影，以及正式依赖组合不出现原型 fixture。
- 设备模型测试覆盖完整端点 Registry、启动串行连接队列、新发现端点顺延、成功设备置顶、手动切换优先和旧快照隔离；XCUITest 场景覆盖状态卡、设备选择 Sheet、即时删除与实时活动入口缺席。
- ActivityKit 既有测试与联合构建记录只维护 checkpoint 健康，不作为 0.3 产品验收。
