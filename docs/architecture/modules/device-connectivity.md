---
last-reviewed: 2026-08-03
---

# 模块：Device Connectivity

## 目的

发现局域网中的 FMO 盒子，管理用户选择的设备端点，通过官方 GEO WebSocket 读取/写入坐标，并生成不含秘密的连接诊断。

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

protocol FmoEndpointStoring: Sendable {
    func load() async -> FmoDeviceEndpoint?
    func save(_ endpoint: FmoDeviceEndpoint?) async
}

protocol FmoConnectionDiagnosing: Sendable {
    func diagnose(_ endpoint: FmoDeviceEndpoint) -> AsyncStream<FmoDiagnosticUpdate>
}
```

发现、GEO 传输、已选端点存储和连接诊断保持分离；`DeviceHomeModel` 只依赖这些协议和 `PhoneLocationProviding`。服务实现使用 Actor，UI 状态归属 `MainActor`，超时策略可替换测试。

Bonjour 端点使用稳定的 `fmo.local` 作为可连接、可持久化的主机身份。服务解析得到的 IPv4/IPv6 地址及接口作用域只属于当前网络路径，不显示、不持久化；每次新连接由系统 mDNS 重新解析。用户手动输入的主机名或 IPv4 则按原值保存。

## 内部结构

- `NWBrowserFmoDeviceDiscovery` 浏览 `_http._tcp`，只接收名称包含 `fmo` 的服务，并将 Network.framework 回调桥接为可取消的 `AsyncThrowingStream`。解析结果只用于取得服务端口，不使用 `debugDescription` 构造主机地址。
- `FmoGeoProtocol` 是不依赖 UI 或网络的值类型编解码器，负责 envelope、历史拼写、坐标与设备错误校验。
- `FmoGeoWebSocketClient` 作为 Actor 串行化请求/响应，并通过可替换 transport 隔离 `URLSessionWebSocketTask`。
- `FmoGeoWebSocketClient` 在传输报告异常断线时同时清除逻辑端点并关闭 transport，后续请求会立即返回未连接，不继续向失效任务发送消息。
- `DeviceHomeModel` 是 `MainActor` 上的可观察状态机，编排发现、连接、读取、单次定位、写入和回读确认。GEO 异常断线会退出已连接状态、清除失效的盒子坐标，但保留目标端点与手机位置供用户重连后继续；定位权限拒绝不会误断开仍然有效的 GEO 连接。
- 本地网络或定位权限被拒绝时，错误状态携带 `openSettings` 恢复动作，界面同时提供“前往设置”和“暂不”，其他错误继续使用普通确认提示。
- `FmoConnectionDiagnoser` 按依赖顺序执行 Wi-Fi、本地主机与 TCP 端口、官方 HTTP 后台和 GEO WebSocket 四步检查；首个失败会停止后续网络操作并把依赖步骤标记为跳过。
- 各探针通过协议注入。Network.framework 负责网络路径、DNS/mDNS 与 TCP 检查，`URLSession` 发送无正文的 HTTP `HEAD` 请求，独立 GEO 客户端完成握手和坐标响应检查。诊断状态通过 `AsyncStream` 实时投影到 `DeviceDiagnosticsModel`，支持取消和重新检查。
- 诊断优先使用当前选择的端点，其次使用发现结果或手动地址；Bonjour 仍以 `fmo.local` 重新解析，不缓存临时 IP。

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
- `FMOc/Features/Device/FmoConnectionDiagnostics.swift`
- `FMOc/Core/Networking/FmoConnectionDiagnosticProbes.swift`
- `FMOc/Features/Device/DeviceHomeModel.swift`
- `FMOc/Features/Device/DeviceDiagnosticsModel.swift`

## 测试

- JSON 编解码固定向量。
- 坐标边界值。
- 未知消息和错误结果。
- WebSocket 请求顺序和响应超时。
- 页面状态机的发现、连接、定位、同步与错误投影。
- 本地网络与定位权限拒绝的恢复动作，以及定位拒绝时保持设备连接。
- 传输异常断线后的客户端失效、首页状态收敛与端点保留。
- 分步诊断的执行顺序、成功证据、首个失败和后续跳过状态。
- Bonjour 端点稳定主机规范化，以及旧版临时 IP 持久化数据的读取迁移。
- UI 自动化覆盖诊断入口整行命中、诊断页呈现、手动地址流程，以及本地网络拒绝时的设置恢复入口。权限场景通过 Debug 依赖注入稳定复现，不改变生产服务组合。
- Bonjour、系统权限、真实 mDNS、异常断线与诊断结果仍需真机验收；自动化覆盖不能替代 iOS 系统权限弹窗和真实网络切换测试。
