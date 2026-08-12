---
last-reviewed: 2026-08-12
---

# 模块：Dashboard

## 目的

把 GEO、ADR-0005 本地只读状态与本地讲话事件聚合成设备页使用的非敏感状态快照，并将当前讲话者安全关联到近期可信 APRS 位置或六位网格中心，驱动横屏方位与地图仪表盘。延迟、管理员与在线人数不进入模型，也不会由原型 fixture 或替代来源填充。ActivityKit 相关类型与扩展当前仅为后续 checkpoint，不提供用户入口或完成度。

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
    // 呼号、服务器、过滤距离、网格、日志数、单一频率、讲话、最新活动与最多 20 条历史。
}

struct DashboardFullscreenPresentation: Equatable, Sendable {
    let target: DashboardFullscreenTarget?
    let recentSpeakers: [DashboardFullscreenHistoryItem]
    static func make(
        dashboard: DashboardSnapshot,
        ownCoordinate: GeoCoordinate?,
        network: FMOV4NetworkSnapshot,
        now: Date,
        aprsFreshness: TimeInterval
    ) -> DashboardFullscreenPresentation
}

actor DashboardStore {
    func beginConnection() -> DashboardSnapshot
    func recordGeoCoordinate(_ coordinate: GeoCoordinate) -> DashboardSnapshot
    func recordGeoDisconnection() -> DashboardSnapshot
    func recordLocalStatus(_ update: DashboardLocalStatusUpdate) -> DashboardSnapshot
    func recordLocalEvent(_ event: FmoLocalEvent) async -> DashboardSnapshot
    func reset() -> DashboardSnapshot
}

protocol DashboardSpeakerLocationStoring: Sendable {
    func location(for callsign: String) async -> DashboardSpeakerLocation?
    func save(_ location: DashboardSpeakerLocation) async
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
- `FmoLocalEventWebSocketClient` 独立连接 `/events`。讲话空闲或断流会把当前讲话者降为非活动状态并保留最后呼号，而不是继续表述为正在讲话；下一位讲话者到来时，旧呼号才由 `qso/history` 进入历史区域。讲话事件提供网格时，本地通过 `MaidenheadGrid.center` 离线计算中心坐标，并按规范化呼号持久化坐标、网格、已解析地区与更新时间；后续不含网格的 `qso/history` 刷新先合并当前快照，再读取该缓存，避免 App 重启后历史位置退化。缓存最多保留 200 个最近更新的呼号，新事件或可信 APRS 关联会覆盖旧位置。`qso/history` 按时间倒序保留最多 20 条讲话轮次，同时维持兼容首页的单一最新活动字段；同一呼号可重复，冷启动处于空闲时可用最新历史填充灰阶主位。
- 状态响应上限 256 KiB，事件帧上限 64 KiB；超限、超时或路由错位会关闭该会话，避免迟到响应污染下一条无请求 ID 的命令。
- 延迟、管理员呼号和在线/最大人数在 0.3 模型与投影中隐藏。
- 首页投影采用已确认的三段式深色卡片：上部以显式白色放大显示呼号，同一行右侧只放横屏全屏入口；设备选择改在导航栏以“绿点、设备名、下箭头”打开统一 Sheet。呼号下方用小号定位/范围图标呈现 Maidenhead 和过滤距离；下部单一大胶囊把当前服务器与最新动态放在一起。动态以规范化呼号作为整行切换身份：说话人变化时纵向替换；同一说话人由讲话转为最近活动时，只在固定槽位内替换图标并把呼号过渡为灰阶。相对时间由系统时间视图刷新。卡片不显示 QSO 数、频率、分隔线、解释性标签或断开操作，字段未知时直接省略而不使用示例值补位。
- `DashboardFullscreenPresentation` 是无状态纯投影：先按规范化基础呼号选取 30 分钟内的可信 APRS 台站，再使用事件六位网格和当前服务器稳定 UID 缩小候选；完整 SSID 精确匹配或最终唯一候选才使用精细坐标。候选冲突、过期或不存在时依次回退到持久化坐标及合法网格中心，三者均不存在才不提供距离或指向。最近讲话按轮次而非呼号去重，排除当前一次后取最新 10 条；SwiftUI 使用“呼号 + 讲话时间”作为稳定行身份执行原生顶部插入过渡。
- 横屏使用 `fullScreenCover`，呈现前通过 `UIWindowScene.requestGeometryUpdate` 请求横屏，退出恢复竖屏；方向请求被拒绝时使用可滚动的竖屏自适应布局并始终保留退出。方位盘只显示随绝对方位旋转的中央无柄箭头；MapKit 地图默认框选双方，拖动或缩放暂停追踪，显式恢复后才重新接管相机。
- 区县/城市文本通过 iOS 26 `MKReverseGeocodingRequest` 异步解析；成功结果与对应坐标一起进入讲话者位置缓存，重启后坐标相同则直接复用。解析失败只回退已缓存地区或“位置未知”，不影响坐标、距离、方位和地图。解析器由 `DashboardAreaResolving` 注入，HTML 轮换数据不进入生产组合。
- ActivityKit 投影、状态机、客户端与独立 Widget Extension target 已形成可编译的探索 checkpoint；主 App target 不依赖、不嵌入该扩展，也不声明实时活动能力。为维持 checkpoint 的编译与单元测试，支持类型仍随主模块编译，但不进入 `AppComposition`，不会读取、创建或恢复活动。0.3 App 不展示入口、不启动活动，后续恢复前须重新经过文档与原型评审并显式恢复 Release composition。

## 数据流

```text
FmoGeoClient.getCoordinate
FmoLocalStatusProviding ─┐
FmoLocalEventStreaming ──┼→ DashboardStore actor ↔ SpeakerLocationStore
                         │                    └→ DashboardSnapshot
validated GeoCoordinate ─┘             └→ MaidenheadLocator
→ DeviceDashboardSummaryView

DashboardSnapshot + deviceCoordinate + FMOV4NetworkSnapshot
→ DashboardFullscreenPresentation
→ DashboardFullscreenView → 方位盘 / MapKit 地图

FmoLocalAudioStreaming → FmoAudioMonitorModel
→ DashboardFullscreenView → 波形 / 可选本地播放
```

## 依赖与边界

- Foundation：时间与 Codable 快照。
- SwiftUI：交付 `DeviceDashboardSummaryView` 与独立 `DashboardFullscreenView`；实时活动管理页隐藏。
- MapKit / CoreLocation：地图、两点连线与 iOS 26 反向地理编码；不启动新的定位会话。已公开讲话者的最近坐标与地区按呼号保存在受限数量的 UserDefaults 缓存中，仅用于重启后恢复仪表盘位置。
- ActivityKit：checkpoint 支持类型仍在主模块编译，但不进入 0.3 运行时组合；WidgetKit 只属于未嵌入的独立扩展 target。
- Device 的 `GeoCoordinate`：已经完成范围校验的输入值。
- Dashboard 状态聚合不持有 WebSocket、Bonjour 或 APRS 传输；只依赖注入的讲话者位置存储协议恢复已知坐标。横屏位置投影读取已验证的 `FMOV4NetworkSnapshot` 与该本地缓存。全屏视图仅消费 Audio 模块注入的类型化音频监视模型，不接触 WebSocket 消息或 PCM 字节。
- `/ws` 状态客户端与 `/events` 事件流位于 Device 网络层，通过类型化值注入 Dashboard；Dashboard 不能发送管理命令或接触原始帧。
- HTML、Preview 与测试 fixture 不进入 Release 依赖组合；生产 App 只由真实服务更新快照。

## 关键文件

- `FMOc/Features/Dashboard/DashboardSnapshot.swift`
- `FMOc/Features/Dashboard/DashboardStore.swift`
- `FMOc/Features/Dashboard/DashboardSpeakerLocationStore.swift`
- `FMOc/Features/Dashboard/MaidenheadLocator.swift`
- `FMOc/Features/Dashboard/DeviceDashboardSummaryView.swift`
- `FMOc/Features/Dashboard/DashboardFullscreenPresentation.swift`
- `FMOc/Features/Dashboard/DashboardFullscreenView.swift`
- `FMOc/Features/Audio/FmoAudioMonitorModel.swift`
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
- 横屏投影测试覆盖 APRS 唯一候选、SSID 冲突不猜测、持久化坐标/网格回退、距离/方位向量、重复呼号讲话轮次及历史讲话的唯一 APRS 坐标关联；位置存储测试覆盖跨实例恢复坐标、网格、地区和无网格历史回填。
- XCUITest 覆盖卡片入口、自动横屏、主要讲话信息、退出恢复竖屏以及导航栏设备选择保持可用。
- 音频测试覆盖 PCM 端序/帧长、保活忽略、异常消息失败关闭、默认静音仍更新波形以及停止后重置声音按钮。
- Debug-only UI 场景验证图标优先的完整首页投影，以及正式依赖组合不出现原型 fixture。
- 设备模型测试覆盖完整端点 Registry、启动串行连接队列、新发现端点顺延、成功设备置顶、手动切换优先和旧快照隔离；XCUITest 场景覆盖状态卡、设备选择 Sheet、即时删除与实时活动入口缺席。
- ActivityKit 既有测试与联合构建记录只维护 checkpoint 健康，不作为 0.3 产品验收。
