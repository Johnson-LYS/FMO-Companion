---
last-reviewed: 2026-08-06
---

# 模块：APRS

## 目的

在 App 活跃期间以只读方式连接 APRS-IS，把严格有界的 TNC2 / FMO V4 输入解析成“尚未验证”的类型化帧，并为后续证书链、CRL、消息签名和 JOINT/EVENT 配对验证提供纯数据边界。

解析成功不等于可信。当前模块只交付传输与纯解析基础，任何 `UnverifiedFMOV4Frame` 均不得直接进入地图、目录、事件流、Dashboard 或危险操作。

## 公共接口

```swift
struct ReceiveOnlyAPRSIdentity: Hashable, Sendable {
    let callsign: String
    let ssid: UInt8
    var loginCallsign: String { get }
}

struct APRSISEndpoint: Hashable, Sendable {
    static let asia: APRSISEndpoint
    let host: String
    let port: UInt16
}

protocol APRSISReceiving: Actor {
    func events(
        identity: ReceiveOnlyAPRSIdentity,
        endpoint: APRSISEndpoint
    ) async -> AsyncThrowingStream<APRSISInboundEvent, Error>
    func disconnect() async
}

enum APRSISInboundEvent: Sendable {
    case sessionReady(serverCallsign: String)
    case frame(UnverifiedFMOV4Frame)
    case rejected(APRSISFrameRejection)
}

protocol ReceiveOnlyAPRSIdentityStoring: Sendable {
    func load() async -> ReceiveOnlyAPRSIdentityConfiguration?
    func saveManual(_ identity: ReceiveOnlyAPRSIdentity) async
    func adoptInherited(_ identity: ReceiveOnlyAPRSIdentity) async
}
```

`APRSISReceiving` 是上层唯一可见的 APRS-IS 会话能力。底层 transport 的 `send` 只用于一次固定登录控制行，不从业务协议暴露，因此 0.4 没有发送 APRS 数据帧的入口。

`FmoNetworkModel` 在 `MainActor` 上管理身份、前台生命周期、登录超时、连接状态与有上限退避。SwiftUI 只读取它投影的“正在连接 / 正在接收 / 等待网络 / 已暂停”，不会接触原始帧、服务器地址或登录实现细节。

## 内部结构

- `ReceiveOnlyAPRSIdentity` 规范化大写 ASCII 呼号，限制 App SSID 为 `0...15`，并确保完整登录呼号不超过 APRS-IS 的 9 字节边界；SSID 0 不写成 `-0`。
- `APRSISProtocol` 只生成 `pass -1`、`filter u/APFMO4` 的固定 CRLF 登录行。只读登录预期服务器返回 `unverified`；这是 APRS-IS 登录状态，不是 FMO PKI 信任结果。
- `NWAPRSISByteTransport` 使用 Network.framework TCP、`TCP_NODELAY` 语义、Actor 隔离和取消感知回调桥接。默认端点是 Tier 2 亚洲区域轮询地址 `asia.aprs2.net:14580`，端点仍可注入测试或配置。
- `APRSISReceiveOnlyClient` 等待服务器 `#` greeting 后发送一次登录，确认匹配当前身份的 `# logresp ... unverified` 后先产生一次 `sessionReady`，随后才接收业务帧。服务器注释不进入业务层；无效 TNC2 与无效 FMO V4 帧只产生无原文的类型化拒绝事件，不中断后续有效帧。
- `UserDefaultsReceiveOnlyAPRSIdentityStore` 持久化普通身份偏好。来源优先级固定为手动身份高于最近可信本地 FMO 呼号；后续设备切换不会覆盖手动值。呼号与 SSID 不是秘密，但不写入日志。
- `FmoNetworkModel` 仅在 App 活跃时建立会话，15 秒内未完成登录会主动断开；断线按 `1 / 2 / 4 / 8 / 15 / 30 / 60` 秒上限退避重连，身份修改和场景切换会取消旧任务。
- `APRSISLineFramer` 按字节处理拆包/粘包，只接受 CRLF，单行上限包含 CRLF 共 512 字节；空行、孤立 CR/LF、非法 UTF-8 和超长行均失败关闭。
- `TNC2PacketParser` 分离来源呼号/SSID、TOCALL、路径和 information 字段，不解释 FMO 语义。
- `FMOV4Parser` 只接受 `APFMO4`、包含 `TCPIP*` 的 POSITION/STATUS，解析 APRS 原始坐标和公开的 `CQ`、`OMCQ`、`VOCAL`、`ONLINE`、`BEACON`、`STATION`、`JOINT`、`EVENT`。它严格检查 token 顺序、字段数量、数值、文本上限及 Base64url 解码长度。
- EVENT 的 `rawStatusPayload` 只作为后续 JOINT `SH` 哈希比对的瞬时输入；不得持久化或记录。

## 数据与信任边界

```text
Network.framework bytes
→ CRLF / 512-byte framing
→ TNC2Packet
→ UnverifiedFMOV4Frame
→ （尚未实现）CERT + CRL + SIG + timeSalt + JOINT/EVENT 验证
→ trusted domain event
```

只有最后的 `trusted domain event` 才能进入地图、目录和事件 UI。Release composition 当前只接入身份编辑与 APRS-IS 会话状态；`UnverifiedFMOV4Frame` 在模型中被消费后丢弃，不进入任何可见内容或缓存。

## 依赖

- Network.framework：APRS-IS TCP。
- Foundation：字节、UTF-8 与流模型。
- 当前没有第三方依赖；确定性 CBOR 与信任材料仍处于 checkpoint。

## 错误与降级

- 连接、发送登录或接收失败：结束当前流，由 `FmoNetworkModel` 显示等待状态并执行可取消、有上限的退避重连。
- greeting 前业务包、身份不匹配、异常登录状态或重复登录响应：协议失败，结束当前流。
- CRLF、UTF-8 或 512 字节边界错误：无法安全重新同步，结束当前流。
- 单个 TNC2 / FMO V4 语义错误：输出无原文的拒绝类别，继续读取下一行。
- 不得将 APRS-IS 的 `unverified` 登录状态转换为“数据不可信”文案，也不得反向把它转换为“FMO 已验证”；两者属于不同层级。

## 当前未实现

- CERT CBOR、证书链、有效期、CRL、Ed25519、timeSalt 和 JOINT/EVENT 配对。
- 可信 reducer、缓存、收藏、地图、目录和事件流。身份 Sheet 与连接状态已进入 SwiftUI，但可信网络内容仍为空状态。

在官方许可证、有效 CRL、CA/CRL 签名规则和完整官方字节向量补齐前，信任验证及可信 UI 继续阻塞。

## 关键文件

- `FMOc/Features/APRS/APRSISReceiveOnlyClient.swift`
- `FMOc/Features/APRS/FmoNetworkModel.swift`
- `FMOc/Features/APRS/FmoNetworkView.swift`
- `FMOc/Features/APRS/ReceiveOnlyAPRSIdentityStore.swift`
- `FMOc/Features/APRS/NWAPRSISByteTransport.swift`
- `FMOc/Features/APRS/APRSISLineFramer.swift`
- `FMOc/Features/APRS/TNC2Packet.swift`
- `FMOc/Features/APRS/FMOV4Parser.swift`

## 测试

- 呼号规范化、SSID 边界和 9 字节登录身份。
- 固定 `pass -1` / `u/APFMO4` 登录行及 `unverified` 登录响应。
- CRLF 拆包、粘包、UTF-8、空行和 512 字节边界。
- TNC2 来源、TOCALL、路径和畸形输入。
- 所有公开 FMO V4 消息家族、坐标、token 顺序、数值、文本及 Base64url 长度。
- greeting → 登录 → 接收顺序、只发送一次登录，以及坏帧不终止有效流。
- 身份持久化与手动优先级、FMO 呼号继承、前后台暂停/恢复、断线等待重连。
- 无身份 → 身份 Sheet → 保存 → 正在接收的 XCUITest 用户流程；0.4 UI 不出现消息、远控或凭据入口。
- Network.framework 真正的公共网络连接仍需使用用户配置的合法呼号做只读集成验收；自动化测试不得使用伪造身份连接公网。
