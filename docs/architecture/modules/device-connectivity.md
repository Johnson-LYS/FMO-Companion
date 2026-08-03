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
```

发现、GEO 传输和已选端点存储保持分离；`DeviceHomeModel` 只依赖这些协议和 `PhoneLocationProviding`。服务实现使用 Actor，UI 状态归属 `MainActor`，超时策略可替换测试。

## 内部结构

- `NWBrowserFmoDeviceDiscovery` 浏览 `_http._tcp`，只接收名称包含 `fmo` 的服务，并将 Network.framework 回调桥接为可取消的 `AsyncThrowingStream`。
- `FmoGeoProtocol` 是不依赖 UI 或网络的值类型编解码器，负责 envelope、历史拼写、坐标与设备错误校验。
- `FmoGeoWebSocketClient` 作为 Actor 串行化请求/响应，并通过可替换 transport 隔离 `URLSessionWebSocketTask`。
- `DeviceHomeModel` 是 `MainActor` 上的可观察状态机，编排发现、连接、读取、单次定位、写入和回读确认。
- 当前诊断入口展示已知连接阶段与可行动错误；独立的 Wi-Fi、DNS、HTTP、WebSocket 分步探测仍属于本里程碑后续工作。

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
- Foundation/URLSession：WebSocket。
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
- `FMOc/Features/Device/DeviceHomeModel.swift`
- `FMOc/Models/GeoCoordinate.swift`

## 测试

- JSON 编解码固定向量。
- 坐标边界值。
- 未知消息和错误结果。
- WebSocket 请求顺序和响应超时。
- 页面状态机的发现、连接、定位、同步与错误投影。
- Bonjour、系统权限和真实 mDNS 使用真机验收；取消、重复连接、断线与诊断的自动化覆盖仍需补齐。
