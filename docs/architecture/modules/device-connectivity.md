---
last-reviewed: 2026-08-17
---

# 模块：Device Connectivity

## 目的

发现局域网中的 FMO 盒子，管理用户选择的设备端点，通过官方 GEO WebSocket 读取/写入坐标，生成不含秘密的连接诊断，并安全路由到盒子官方管理与 QSO 页面。

## 公共接口

```swift
struct FmoDeviceEndpoint: Hashable, Sendable {
    let host: String
    let port: Int?
    let source: Source
    let name: String?
}

protocol FmoDeviceDiscovering: Sendable {
    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, Error>
}

protocol FmoGeoClient: Sendable {
    func connect(to endpoint: FmoDeviceEndpoint) async throws
    func getCoordinate() async throws -> GeoCoordinate
    func setCoordinate(_ coordinate: GeoCoordinate) async throws
    func disconnect() async
}

protocol FmoStationControlling: Sendable {
    func connect(to endpoint: FmoDeviceEndpoint) async throws
    func getServerCatalog() async throws -> FmoDeviceServerCatalog
    func getServerCatalog(
        onUpdate: @escaping @Sendable (FmoDeviceServerCatalog) async -> Void
    ) async throws -> FmoDeviceServerCatalog
    func switchCurrentServer(toUID uid: Int64) async throws -> FmoCurrentServer
    func disconnect() async
}

struct FmoEndpointRegistry: Codable, Equatable, Sendable {
    let endpoints: [FmoDeviceEndpoint]
    let lastSuccessfulEndpointID: String?
}

protocol FmoEndpointStoring: Sendable {
    func loadRegistry() async -> FmoEndpointRegistry
    func saveRegistry(_ registry: FmoEndpointRegistry) async
}

protocol FmoConnectionDiagnosing: Sendable {
    func diagnose(_ endpoint: FmoDeviceEndpoint) -> AsyncStream<FmoDiagnosticUpdate>
}

protocol FmoOfficialWebURLBuilding: Sendable {
    func url(for page: FmoOfficialPage, endpoint: FmoDeviceEndpoint) throws -> URL
}
```

发现、GEO 传输、已选端点存储、连接诊断和官方页面路由保持分离；`DeviceHomeModel` 依赖设备服务协议、`PhoneLocationProviding` 与 Dashboard 聚合 Actor。服务实现使用 Actor，UI 状态归属 `MainActor`，超时策略与 URL 构造可替换测试。

Bonjour 端点使用稳定的 `fmo.local` 作为可连接、可持久化的主机身份。服务解析得到的 IPv4/IPv6 地址及接口作用域只属于当前网络路径，不显示、不持久化；每次新连接由系统 mDNS 重新解析。用户手动输入的主机名或 IPv4 则按原值保存。

发现结果以 `FmoDeviceEndpoint.id`（规范化主机与有效端口）合并到持久化的完整设备列表，不清空手动输入或已保存端点；同一 `fmo.local:80` 的手动与 Bonjour 表达只保留已有项。`FmoEndpointRegistry` 对端点去重，并把有效的最后成功设备规范化到首位；旧版单一 `selectedFmoEndpoint` 数据在首次读取时迁移为 Registry。用户移除设备时按同一稳定身份从列表立即删除；若它是当前目标则先断开 GEO，并清除最后成功标记。移除不是 Bonjour 屏蔽规则，设备仍在线时可在下一次发现中重新出现。

## 内部结构

- `NWBrowserFmoDeviceDiscovery` 浏览 `_http._tcp`，只接收名称包含 `fmo` 的服务，并将 Network.framework 回调桥接为可取消的 `AsyncThrowingStream`。解析结果只用于取得服务端口，不使用 `debugDescription` 构造主机地址。
- `FmoGeoProtocol` 是不依赖 UI 或网络的值类型编解码器，负责 envelope、历史拼写、坐标与设备错误校验。
- `FmoGeoWebSocketClient` 作为 Actor 串行化请求/响应，并通过可替换 transport 隔离 `URLSessionWebSocketTask`。
- `FmoGeoWebSocketClient` 在传输报告异常断线时同时清除逻辑端点并关闭 transport，后续请求会立即返回未连接，不继续向失效任务发送消息。
- `DeviceHomeModel` 是 `MainActor` 上的可观察状态机，编排发现、连接、读取、单次定位、写入和回读确认。发现与连接使用相互独立、可取消的任务及代际标识：停止扫描不取消已经选定的连接，切换设备则会取消旧连接结果，避免迟到响应覆盖新目标。GEO 异常断线会退出已连接状态、清除失效的盒子坐标，但保留目标端点与手机位置供用户重连后继续；定位权限拒绝不会误断开仍然有效的 GEO 连接。
- App 进入后台时，`DeviceHomeModel` 停止 Bonjour 发现、尚未完成的自动连接尝试和三秒当前服务器轮询；已经建立的 GEO、状态和事件 WebSocket、设备连接相位及 Dashboard 当前内容保持不变，不因生命周期事件主动断开或显示“重新连接”。回到前台后立即回读完整本地状态，再恢复发现与低频轮询；若保留的状态 WebSocket 首次读取失败，则只重建该状态链路并重试一次，不改变整台设备的连接相位。由此可在盒子后台切换服务器后立即刷新卡片，同时避免预先把设备标记离线。声音开启时音频与事件接收可随合法后台音频执行继续处理；静音时不承诺 iOS 持续调度或固定刷新。
- 完成初始本地状态读取后，`DeviceHomeModel` 在前台连接存续期间以默认 3 秒间隔复用独立状态会话，仅调用 ADR-0005 白名单中的 `station/getCurrent`；会话失效时由下一轮重新连接，使用户直接在盒子上切换服务器后首页能在下一轮刷新时更新。刷新等待器与间隔可注入且可取消；切换设备或停止连接会取消旧任务，迟到结果不能写入新设备快照。
- 单次当前服务器刷新失败只把本地状态链路标为过期，不影响 GEO 与 `/events`；下一轮先尝试完整只读状态快照以恢复该链路。ADR-0005 状态会话不发送 `station/setCurrent`，也不把轮询扩大到 QSO、频率或其他管理命令。
- `FmoStationControlWebSocketClient` 是 ADR-0010 批准的独立 Actor：每次打开选择器都重新分页读取设备 `getListRange` 与 `getPinnedList`，不使用跨会话缓存；每个实时分页通过校验后立即投影当前累计目录，使首批服务器先显示、后续页继续加载。客户端只允许从本次已读目录选择正整数 UID，并以 `setCurrent` 后 `getCurrent` UID 匹配作为成功条件。分页、单帧、名称与总数均有上限；切设备或断开时关闭独立会话，旧响应不能覆盖新设备。
- GEO 坐标读取或同步回读成功后，`DeviceHomeModel` 把已校验坐标交给 `DashboardStore` 派生 Maidenhead；它不自行构造服务器、频率、延迟或事件字段。
- `DeviceHomeModel` 同时负责端点集合的稳定身份合并、排序、持久化和显式移除；发现流只追加新身份。删除当前端点会收敛连接状态、清除最后成功标记，并明确停止本轮自动队列，不自动切换到其他设备。
- App 首页出现时并行启动发现与自动连接队列。队列先放最后一次完成 GEO 连接并成功回读坐标的稳定端点，再按原顺序放其余保存端点；新发现端点去重后追加。连接严格串行，单台失败只记录为候选错误，队列与扫描均耗尽后才呈现总体失败；队列已经耗尽后出现新发现端点时继续尝试。任一设备成功后移动到首位并停止自动队列，后续发现只更新列表。用户点击当前设备是幂等操作，点击其他设备会取消自动队列和旧连接结果并优先切换目标；首页不提供主动断开按钮。
- 首页只保留状态卡。扫描结果、手动地址、重新扫描、设备切换与左滑删除统一放在导航栏设备按钮打开的原生 Sheet 中；当前服务器名称打开另一原生 Sheet，按设备收藏/全部服务器分组并支持搜索和刷新。连接过程中仍允许用户显式选择其他端点，以保证手动选择优先。
- 本地网络或定位权限被拒绝时，错误状态携带 `openSettings` 恢复动作，界面同时提供“前往设置”和“暂不”，其他错误继续使用普通确认提示。
- `FmoConnectionDiagnoser` 按依赖顺序执行 Wi-Fi、本地主机与 TCP 端口、官方 HTTP 后台和 GEO WebSocket 四步检查；首个失败会停止后续网络操作并把依赖步骤标记为跳过。
- 各探针通过协议注入。Network.framework 负责网络路径、DNS/mDNS 与 TCP 检查，`URLSession` 发送无正文的 HTTP `HEAD` 请求，独立 GEO 客户端完成握手和坐标响应检查。诊断状态通过 `AsyncStream` 实时投影到 `DeviceDiagnosticsModel`，支持取消和重新检查。
- 诊断优先使用当前选择的端点，其次使用发现结果或手动地址；Bonjour 仍以 `fmo.local` 重新解析，不缓存临时 IP。
- 诊断探针使用独立连接验证网络路径，不代表首页 GEO 会话已建立。诊断页必须同时显示首页当前会话状态；四步全部通过只表述为“设备可达”。
- `FmoOfficialWebURLBuilder` 只能从已验证 `FmoDeviceEndpoint` 构造 HTTP `/` 或 `/qso.html`；Bonjour 继续使用稳定 `fmo.local`，不会把解析到的临时 IP 写入 URL 或存储。
- `OfficialWebModel` 负责无设备、无效端点和待呈现目标状态，`SafariView` 只把目标交给 `SFSafariViewController`。App 不使用自定义 WebView、不注入脚本，也不读取官方页面 DOM。

## GEO 协议

端点：

```text
ws://<host>/ws
```

请求/响应子类型：

| 操作 | 请求 | 响应 |
|---|---|---|
| 读取 | `getCordinate` | `getCordinateResponse` |
| 写入 | `setCordinate` | `setCordinateResponse` |

通用 envelope：

```json
{
  "type": "config",
  "subType": "setCordinate",
  "data": {
    "latitude": 25.040000,
    "longitude": 102.710000
  },
  "code": 0
}
```

`Cordinate` 必须按设备历史拼写发送。坐标范围：纬度 `-90...90`，经度 `-180...180`。

## 依赖

- Network.framework：Bonjour 和端点解析。
- Foundation/URLSession：HTTP 可达性和 WebSocket。
- SafariServices：以系统标准界面呈现官方管理与 QSO 页面。
- Core Location 由上层 Location 模块使用，不由本模块直接请求权限。

## 错误模型

至少区分：

- 本地网络权限拒绝。
- 未连接适用网络。
- 发现超时。
- DNS/mDNS 解析失败。
- WebSocket 握手失败。
- 连接中断。
- 响应超时。
- JSON/envelope 格式错误。
- 未知响应类型。
- 坐标越界。
- 设备返回失败结果。

## 关键文件

- `FMOc/Features/Device/FmoDeviceServices.swift`
- `FMOc/Features/Device/NWBrowserFmoDeviceDiscovery.swift`
- `FMOc/Features/Device/FmoGeoWebSocketClient.swift`
- `FMOc/Features/Device/FmoStationControlProtocol.swift`
- `FMOc/Features/Device/FmoStationControlWebSocketClient.swift`
- `FMOc/Features/Device/DeviceServerPickerView.swift`
- `FMOc/Features/Device/FmoConnectionDiagnostics.swift`
- `FMOc/Core/Networking/FmoConnectionDiagnosticProbes.swift`
- `FMOc/Features/Device/DeviceHomeModel.swift`
- `FMOc/Features/Device/DeviceDiagnosticsModel.swift`
- `FMOc/Features/Device/OfficialWebModel.swift`
- `FMOc/Features/Device/SafariView.swift`
- `FMOc/Features/Dashboard/DashboardStore.swift`

## 测试

- JSON 编解码固定向量。
- 坐标边界值。
- 未知消息和错误结果。
- WebSocket 请求顺序和响应超时。
- 页面状态机的发现、连接、定位、同步与错误投影。
- GEO 成功、断线与设备移除时的 Dashboard 快照投影和旧设备隔离。
- 本地网络与定位权限拒绝的恢复动作，以及定位拒绝时保持设备连接。
- 传输异常断线后的客户端失效、首页状态收敛与端点保留。
- 分步诊断的执行顺序、成功证据、首个失败和后续跳过状态。
- Bonjour 端点稳定主机规范化，以及旧版临时 IP 持久化数据的读取迁移。
- 发现时保留手动/已保存端点、稳定身份去重，以及移除当前端点时断开并清除持久化。
- 完整端点 Registry 的去重、旧版单端点迁移、最后成功设备置顶，以及删除后的持久化收敛。
- 启动时按“最后成功、其余保存、新发现”串行自动连接，失败顺延、首个发现自动连接、成功后不切换，以及用户显式选择其他设备时取消自动队列并切换。
- 已连接设备进入后台时不增加 GEO 连接次数、不关闭本地会话且 Dashboard 字段保持当前；恢复前台立即读取后台期间变更的服务器，状态连接失效时单独重建一次；未连接时停止发现/自动尝试，返回前台后再按既有优先级恢复。
- 官方管理与 QSO URL 的确定性构造、无设备/无效地址恢复提示，以及 `SFSafariViewController` 呈现入口。
- UI 自动化场景覆盖诊断入口整行命中、未连接会话与独立探测说明、首页无常驻设备列表、状态卡打开设备选择 Sheet、启动连接队列、手动地址流程、已保存设备原生左滑立即删除，以及本地网络拒绝时的设置恢复入口。场景通过 Debug 依赖注入稳定复现，不改变生产服务组合。
- Bonjour、系统权限、真实 mDNS、异常断线与诊断结果已完成阶段真机验收；后续系统版本和网络环境变化仍需保留真机回归，自动化覆盖不能替代 iOS 系统权限弹窗和真实网络切换测试。
