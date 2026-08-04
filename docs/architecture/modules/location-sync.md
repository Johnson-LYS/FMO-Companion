---
last-reviewed: 2026-08-04
---

# 模块：Location Sync

## 目的

把 iPhone 的位置事件转换为可解释、可取消的 FMO 坐标同步决策。模块拥有定位授权、模式、节流和自动同步生命周期，但不解析 GEO 协议，也不持久化精确坐标。

## 公共接口

当前已实现的领域与平台边界：

```swift
enum LocationSyncMode: String, Codable, Sendable {
    case manual
    case lowPower
    case vehicle
}

struct LocationSyncSample: Equatable, Sendable {
    let coordinate: GeoCoordinate
    let timestamp: Date
}

struct LocationSyncEvaluator: Sendable {
    func evaluate(
        mode: LocationSyncMode,
        candidate: LocationSyncSample,
        lastSuccessfulSync: LocationSyncSample?
    ) -> LocationSyncDecision
}

protocol AutomaticLocationProviding: Sendable {
    func updates(
        for mode: LocationSyncMode
    ) async throws -> AsyncThrowingStream<AutomaticLocationEvent, Error>
    func stop() async
}

protocol LocationSyncModeStoring: Sendable {
    func load() async -> LocationSyncMode
    func save(_ mode: LocationSyncMode) async
}

@MainActor
protocol LocationAuthorizationReading: Sendable {
    func currentStatus() -> LocationAuthorizationState
}

actor AutomaticLocationSyncCoordinator {
    func restore() async
    func start(mode: LocationSyncMode) async
    func stop() async
    func resume()
    func currentSnapshot() -> AutomaticLocationSyncSnapshot
    func snapshots() -> AsyncStream<AutomaticLocationSyncSnapshot>
}

protocol AutomaticLocationSyncCoordinating: Sendable {
    func restore() async
    func start(mode: LocationSyncMode) async
    func stop() async
    func resume() async
    func currentSnapshot() async -> AutomaticLocationSyncSnapshot
    func snapshots() async -> AsyncStream<AutomaticLocationSyncSnapshot>
}

@MainActor
final class LocationAutomationModel {
    func restoreIfNeeded() async
    func select(_ mode: LocationSyncMode) async
    func stop() async
    func resume() async
    func refreshAuthorization()
}
```

现有 `PhoneLocationProviding` 继续承担用户主动触发的一次性定位，避免自动定位开发改变 0.1 的手动同步行为。自动事件、授权读取与模式存储分别通过协议隔离；后续同步协调器必须继续通过协议依赖 `FmoGeoClient`、网络路径、时钟和等待器。

## 行为不变量

- 手动模式永不由位置事件自动同步。
- 低功耗模式采用 15 分钟或 1 公里，车载模式采用 2 分钟或 250 米；两项阈值为 OR 关系。
- 自动模式收到首个有效事件时立即同步；之后只以最后一次成功同步作为节流检查点，失败尝试不推进检查点。
- 节流只处理 Core Location 已交付的事件，不创建承诺固定周期的定时器。
- 用户停止、模式切换和权限失效必须通过结构化并发取消位置、退避、连接与发送任务。
- 离网时只在内存中覆盖最新有效位置；模式和有限状态可以持久化，精确坐标不得为补发而落盘。

## 内部结构

- `LocationSyncMode` 提供固定模式预设和授权需求，不承载用户可见文案。
- `LocationSyncPolicy` 对带时间戳坐标执行确定性阈值判定，并返回首次、时间、距离、双阈值或节流原因。
- 距离使用 WGS84 坐标上的球面 Haversine 近似，只服务于节流；不用于导航或测绘展示。
- `CoreLocationProvider` 使用使用期间授权的 `CLServiceSession` 与 `.default` 配置获取一次位置。
- `CoreLocationAutomaticProvider` 作为 Actor 持有始终授权的 `CLServiceSession`、`CLBackgroundActivitySession`、位置更新与诊断任务；低功耗使用 `.default`，车载使用 `.automotiveNavigation`。
- 自动事件源把系统诊断映射为类型化暂停原因，位置流结束、用户停止或新流替换旧流时统一取消任务并失效会话。
- `CoreLocationAuthorizationReader` 在 `MainActor` 读取系统授权状态；手动模式接受使用期间或始终授权，自动模式只接受始终授权。
- `UserDefaultsLocationSyncModeStore` 只保存模式枚举原始值，无值或未知值回退到手动模式，不保存坐标。
- `Info.plist` 声明显式定位会话、始终定位用途文案与 `location` 后台模式；所有定位入口必须持有相应 `CLServiceSession`。
- `NWPathNetworkObserver` 将 Network.framework 路径状态转换为最新值流；它只判断系统网络路径是否可用，设备端点是否真正可达仍由 GEO 连接结果决定，因此支持用户授权的代理路径。
- `AutomaticLocationSyncCoordinator` 串联位置、路径、端点、GEO、模式存储、时钟与等待器。离网会取消发送并断开 GEO；恢复后只启动一个发送任务并使用最新内存位置。
- 每次 GEO 失败先断开失效连接，再按 1、2、4、8、16、30、60 秒退避，之后封顶 60 秒；网络离开、用户停止和模式切换都能取消等待。
- `AutomaticLocationSyncSnapshot` 分开记录运行阶段、最后一次尝试和最后成功时间；失败不会推进私有坐标检查点，也不会覆盖最后成功时间。
- `LocationAutomationModel` 订阅快照流并把授权、模式、暂停原因、最后尝试与最后成功投影给 SwiftUI；自动模式在触发系统授权前先由页面解释固定阈值与功耗差异，手动模式保留 0.1 的一次性入口。
- `AppComposition` 为首页与自动协调器注入同一个 `FmoEndpointStoring`，但使用相互独立的 GEO 客户端，避免后台短连接改变首页会话状态。根视图启动时仅恢复一次已保存模式，回到前台只刷新授权显示，不停止后台会话。

## 依赖

- Foundation：时间戳和纯值计算。
- Core Location：授权、位置事件和后台活动会话，仅由平台适配器使用。
- Device Connectivity：通过 `FmoGeoClient` 发送已通过策略的坐标。
- Network.framework：通过可注入路径来源门控重连，不由节流策略直接依赖。

## 关键文件

- `FMOc/Features/Location/LocationSyncPolicy.swift`
- `FMOc/Features/Location/AutomaticLocationProvider.swift`
- `FMOc/Features/Location/AutomaticLocationSyncCoordinator.swift`
- `FMOc/Features/Location/AutomaticLocationSyncSupport.swift`
- `FMOc/Features/Location/LocationAutomationModel.swift`
- `FMOc/Features/Location/LocationAutomationView.swift`

## 测试

- 固定预设与授权需求。
- 手动模式禁止自动发送。
- 自动模式首个事件立即同步。
- 时间/距离阈值的精确边界和 OR 语义。
- 系统授权映射、各模式所需授权、模式存储回退与往返。
- 自动事件源拒绝手动模式，空闲停止可重复执行；真实诊断事件仍需 Simulator 场景和真机覆盖。
- 协调器覆盖离网不发送、恢复补发、成功检查点节流、连接失败退避、无设备暂停和停止取消。
- 退避上限、最后尝试/成功分离及单发送任务由确定性替身验证。
- UI 模型覆盖单次恢复、模式切换、停止和快照订阅；XCUITest 覆盖权限前说明与模式入口。
- 后台、锁屏、离网与恢复必须在真实 iPhone + FMO 环境验收，Simulator 单元测试不能替代系统调度验证。
