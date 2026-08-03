---
last-reviewed: 2026-08-03
---

# 模块：Device Connectivity

## 目的

发现局域网中的 FMO 盒子，管理用户选择的设备端点，通过官方 GEO WebSocket 读取/写入坐标，并生成不含秘密的连接诊断。

## 计划公共接口

```swift
struct FmoDeviceEndpoint: Hashable, Sendable {
    let host: String
    let port: Int?
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
```

接口名称可以在实施时调整，但必须保持以下边界：发现与 GEO 传输分离；UI 只依赖协议；时间、超时和连接实现可替换测试。

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

实施后更新本节。预期首批文件：

- `FMOc/Features/Device/FmoDeviceDiscovery.swift`
- `FMOc/Features/Device/FmoGeoClient.swift`
- `FMOc/Models/GeoCoordinate.swift`
- `FMOcTests/Device/FmoGeoProtocolTests.swift`

## 测试

- JSON 编解码固定向量。
- 坐标边界值。
- 未知消息和错误结果。
- 超时、取消、重复连接和断线。
- Bonjour 发现逻辑使用浏览器抽象测试；真实 mDNS 使用真机验收。
