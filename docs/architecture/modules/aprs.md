---
last-reviewed: 2026-08-14
---

# 模块：APRS

## 目的

在 App 活跃期间通过彼此隔离的 APRS-IS 会话提供两类能力：0.4 只读会话把严格有界的 TNC2 / FMO V4 输入验证为台站、公共服务器和事件；0.6 验证登录写会话只处理标准点对点消息、ACK/REJ 与固定 FMO 远控帧。两者共享字节 transport 与 TNC2 基础类型，但不共享登录状态机或业务发送入口。

解析成功不等于可信。任何 `UnverifiedFMOV4Frame` 都必须通过 CERT、官方证书链、有效期、CRL、报文 Ed25519、`timeSalt` 与必要的 JOINT/EVENT 关系验证，才可进入可见业务快照；验证失败只累计无原文诊断类别。

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

protocol APRSISMessaging: Actor {
    func events(
        identity: ReceiveOnlyAPRSIdentity,
        endpoint: APRSISEndpoint
    ) async -> AsyncThrowingStream<APRSISMessagingEvent, Error>
    func send(packet: String) async throws
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

protocol FMOV4NetworkProcessing: Actor {
    func process(_ frame: UnverifiedFMOV4Frame, at date: Date) async -> FMOV4NetworkSnapshot
    func snapshot() -> FMOV4NetworkSnapshot
}

protocol FMOV4RevocationChecking: Actor {
    func check(
        user: FMOV4UserCertificate,
        intermediate: FMOV4IntermediateCertificate,
        root: FMOV4RootCertificate,
        at date: Date
    ) async -> FMOV4RevocationResult
}
```

`APRSISReceiving` 仍是 FMO V4 网络唯一可见的只读会话；其底层 `send` 只用于固定 `pass -1` 登录。`APRSISMessaging` 是单独的验证写会话，只接受经过类型化编解码器生成且通过 512 字节/CRLF 校验的完整 APRS 数据帧。地图、目录和事件层无法取得写会话，消息层也无法绕过标准消息与三种远控命令生成任意帧。该边界由 ADR-0006 固定。

`FmoNetworkModel` 在 `MainActor` 上管理身份、前台生命周期、登录超时、连接状态、有上限退避和 `FMOV4NetworkSnapshot`。SwiftUI 只读取会话状态和验证后的快照，不接触原始帧、证书 blob 或登录实现细节。

## 内部结构

- `ReceiveOnlyAPRSIdentity` 规范化大写 ASCII 呼号，限制 App SSID 为 `0...15`，并确保完整登录呼号不超过 APRS-IS 的 9 字节边界；SSID 0 不写成 `-0`。
- `APRSISProtocol` 只生成 `pass -1`、`filter u/APFMO4` 的固定 CRLF 登录行。只读登录预期服务器返回 `unverified`；这是 APRS-IS 登录状态，不是 FMO PKI 信任结果。
- `APRSISPasscode` 按规范化基础呼号计算公开 PASSCODE，SSID 不参与；结果按需生成，不进入 Keychain、UserDefaults、SwiftData、日志或诊断。
- `APRSISMessagingProtocol` 生成验证登录和 `g/<CALL-SSID>` 消息过滤器，只接受身份匹配的 `verified` 响应；`APRSISMessagingClient` 与 0.4 接收器使用独立 transport、取消任务和登录状态。
- `APRSMessageCodec` 独立处理 `APFMO0` TOCALL、9 字节收件地址、最多 60 UTF-8 字节正文、1–5 位 ASCII 消息 ID、`ack` 与 `rej`。控制字符与 `{` 在发送前拒绝；中文等合法 UTF-8 不再被入站解析器静默丢弃。ACK 只按对端完整地址和消息 ID 关联；重复入站消息只落库一次，但每次仍回应 ACK。
- `APRSMessageModel` 仅在 App 活跃且身份存在时维持写会话。发出消息最多自动重试 2 次；退到后台、身份变化或重试耗尽会把等待项收敛为“未确认”，不会在下次启动静默补发。组合根在首次前台任务中明确激活两条 APRS 会话，并以 `didBecomeActive` / `didEnterBackground` 通知重放生命周期；FMO 网络页出现时再次幂等确认激活，避免冷启动的 ScenePhase 时序使稍后保存的身份永久停在“已暂停”。
- `APRSMessageRecord` 使用 SwiftData 保存本机消息历史、方向与确认状态；PASSCODE 和远控 SECRET 不进入数据模型。会话列表从消息记录按对端聚合，系统左滑删除会删除该对端本机历史。
- `NWAPRSISByteTransport` 使用 Network.framework TCP、`TCP_NODELAY` 语义、Actor 隔离和取消感知回调桥接。默认端点是 Tier 2 亚洲区域轮询地址 `asia.aprs2.net:14580`，端点仍可注入测试或配置。
- `APRSISReceiveOnlyClient` 等待服务器 `#` greeting 后发送一次登录，确认匹配当前身份的 `# logresp ... unverified` 后先产生一次 `sessionReady`，随后才接收业务帧。服务器注释不进入业务层；无效 TNC2 与无效 FMO V4 帧只产生无原文的类型化拒绝事件，不中断后续有效帧。
- `UserDefaultsReceiveOnlyAPRSIdentityStore` 持久化普通身份偏好。来源优先级固定为手动身份高于最近可信本地 FMO 呼号；后续设备切换不会覆盖手动值。呼号与 SSID 不是秘密，但不写入日志。
- `FmoNetworkModel` 仅在 App 活跃时建立会话，15 秒内未完成登录会主动断开；断线按 `1 / 2 / 4 / 8 / 15 / 30 / 60` 秒上限退避重连，身份修改和场景切换会取消旧任务。
- `APRSISLineFramer` 按字节处理拆包/粘包，只接受 CRLF，单行上限包含 CRLF 共 512 字节；空行、孤立 CR/LF、非法 UTF-8 和超长行均失败关闭。
- `TNC2PacketParser` 分离来源呼号/SSID、TOCALL、路径和 information 字段，不解释 FMO 语义。
- `FMOV4Parser` 只接受 `APFMO4`、包含 `TCPIP*` 的 POSITION/STATUS，按 APRS 未压缩位置格式读取坐标、symbol table 与 symbol code；FMO 注释从 symbol code 后立即开始，不假设额外分隔空格。随后解析公开的 `CQ`、`OMCQ`、`VOCAL`、`ONLINE`、`BEACON`、`STATION`、`JOINT`、`EVENT`，并严格检查 token 顺序、字段数量、数值、文本上限及 Base64url 解码长度。
- `DeterministicCBOR` 只支持 FMO 所需的无符号整数、字节串、文本、固定数组与布尔值；编码使用最短形式，解码拒绝 map/tag/float/负数/不定长/尾随字节、过深嵌套和超限长度。
- `FMOV4TrustMaterial.official` 内置官方 Root #1 与 Intermediate #1001。启动时预条件验证 Root 自签名和 Intermediate 签名；信任材料以 issuer SN 字典注入，后续轮换不依赖硬编码单例查找。
- `OfficialFMOV4CRLStore` 从证书声明的官方 HTTPS URL 获取 Root/Intermediate CRL，单响应上限 256 KiB、四小时刷新。`{}` 映射为 `notPublished`；签名列表分为 current/stale，断网分为 unavailable，格式或签名错误为 invalid。已有签名缓存不会被 `{}` 或较低 CRL number 覆盖。
- `FMOV4Verifier` 按 Root → Intermediate → User → CRL → Message 的顺序验证，检查呼号绑定、UID 范围、STATION 国家范围、有效期、Ed25519 与 `timeSalt ±1`。通过签名但 CRL 过期/不可用的帧保留 `revocationStale` / `revocationUnavailable`，不得显示为完全可信；已吊销或非法 CRL 直接拒绝。
- `FMOV4NetworkStore` 用稳定签名摘要去重，事件采用最近 24 小时且最多 200 条的双重上限，其他短期实体与 JOINT 也保持有界。EVENT 的 `rawStatusPayload` 只在内存中计算 SHA-256 并匹配同来源、UID 与 TTL 内 JOINT，不持久化或记录。
- `FavoriteCallsign` 按规范化基础呼号唯一化并使用 SwiftData，与短期网络快照分离；取消收藏不删除业务记录。公共 APRS 服务器不再拥有 App 独立收藏，设备服务器收藏由 ADR-0010 从所选 FMO 读取。
- SwiftUI 始终显示 MapKit 地图；`FmoNetworkMapModel` 通过注入的 `PhoneLocationProviding` 获取一次本机位置，并以 Haversine 距离把完整验证快照统一裁剪为全网或 `50...5000 km` 的台站、服务器和事件视图。初始范围为 `500 km`，首次进入已配置页面时自动定位；失败则把范围回退为全网并保留可见错误，避免有限范围标签与实际数据不一致。此后右上角 Menu 选择有限范围时按需定位；左下追踪只控制相机随新台站移动，右下定位更新蓝色本机标记与范围中心。所有控制都不改变 `u/APFMO4` 订阅、不套用盒子过滤器，也不写入设备。目录支持台站/服务器/收藏分段和直接搜索，事件流支持全部规划类型与收藏筛选，详情页展示位置、频率、最近活动与数据时间。证书链、CRL、签名与可信等级当前不进入用户界面。

## 数据与信任边界

```text
Network.framework bytes
→ CRLF / 512-byte framing
→ TNC2Packet
→ UnverifiedFMOV4Frame
→ strict CBOR + CERT + official chain + CRL + SIG + timeSalt
→ FMOV4NetworkStore（JOINT/EVENT、去重、有上限缓存）
→ FMOV4NetworkSnapshot
→ MapKit / directory / events / station details
```

```text
App active + APRS identity
→ on-demand PASSCODE + verified APRS-IS session + g/CALL-SSID filter
→ strict APRS message codec
↔ typed message / ACK / REJ
→ APRSMessageModel（去重、最多 2 次重试、前后台取消）
→ SwiftData history / conversation UI
```

只有 `FMOV4Verifier.accepted` 才能进入 `FMOV4NetworkStore` 的业务记录。Release composition 注入真实 verifier、官方信任材料和 CRL store；UI 测试注入人工快照，不以未验证协议输入制造“可信”结果。

## 依赖

- Network.framework：APRS-IS TCP。
- Foundation：字节、UTF-8、URLSession 与流模型。
- CryptoKit：SHA-256 与 Ed25519。
- SwiftData：呼号收藏与本机消息历史；旧 `FavoriteServer` 类型仅暂留作已安装数据兼容，不再由 UI 读写。
- MapKit：验证后台站地图。
- 当前没有第三方依赖。

## 错误与降级

- 连接、发送登录或接收失败：结束当前流，由 `FmoNetworkModel` 显示等待状态并执行可取消、有上限的退避重连。
- greeting 前业务包、身份不匹配、异常登录状态或重复登录响应：协议失败，结束当前流。
- CRLF、UTF-8 或 512 字节边界错误：无法安全重新同步，结束当前流。
- 单个 TNC2 / FMO V4 语义错误：输出无原文的拒绝类别，继续读取下一行。
- 未知 issuer、证书/报文签名失败、有效期/范围不符、吊销和非法 CRL：拒绝业务输入并增加类型化计数，不保存原始帧。
- CRL 地址返回 `{}`：没有签名缓存时记录内部 `notPublished` 状态；已有签名缓存时继续使用缓存。
- CRL 已签名但过期或网络暂不可用：保留密码学认证结果和内部降级状态，不向普通用户展示技术警告；如果列表中已命中吊销仍直接拒绝。
- 重复签名或无法在期限内匹配 JOINT/EVENT：静默丢弃，不重复展示也不保存原始状态文本。
- 不得将 APRS-IS 的 `unverified` 登录状态转换为“数据不可信”文案，也不得反向把它转换为“FMO 已验证”；两者属于不同层级。
- 写会话返回 `unverified`、身份不匹配或异常登录格式：拒绝发送并进入可恢复等待；不得降级成只读 PASSCODE 或跳过验证。
- 消息 ACK 迟到或重复：只更新地址和 ID 同时匹配的出站记录；已经因后台/身份变化关闭的旧消息不重新发送。

## 发布前跟踪

- 0.4 已使用用户合法呼号完成真实 APRS-IS `APFMO4` 数据接收、地图/目录/事件与收藏真机验收；146 项单元测试与 14 项 XCUITest 通过。
- 0.6 消息、ACK/REJ、隔离写会话、SwiftData 历史与消息 UI 已完成。首轮消息真机反馈暴露 `APFMC0` 与 7-bit ASCII 假设不兼容 FMO，按 `APFMO0 + 60 字节 UTF-8` 修正；首轮 162 项单元测试与 11 条 XCUITest、修正后实际源码兼容向量、测试目标编译及用户消息/远控真机复验共同关闭该里程碑。
- 补充官方未省略的 APRS CERT/SIG 字节向量，作为第二实现交叉验证。
- 发布前确认官方 Root/Intermediate 证书所声明的独立许可证 URL；当前两个 URL 仍为 404。
- Intermediate CRL #4 当前已过 `nextUpdate`；内部保留过期状态但 UI 暂不展示，等待官方轮换后验证自动刷新路径。

## 关键文件

- `FMOc/Features/APRS/APRSISReceiveOnlyClient.swift`
- `FMOc/Features/APRS/APRSISMessagingClient.swift`
- `FMOc/Features/APRS/APRSMessageModel.swift`
- `FMOc/Features/APRS/APRSMessageProtocol.swift`
- `FMOc/Features/APRS/APRSMessagesView.swift`
- `FMOc/Features/APRS/FmoNetworkModel.swift`
- `FMOc/Features/APRS/FmoNetworkView.swift`
- `FMOc/Features/APRS/FmoNetworkMapModel.swift`
- `FMOc/Features/APRS/ReceiveOnlyAPRSIdentityStore.swift`
- `FMOc/Features/APRS/NWAPRSISByteTransport.swift`
- `FMOc/Features/APRS/APRSISLineFramer.swift`
- `FMOc/Features/APRS/TNC2Packet.swift`
- `FMOc/Features/APRS/FMOV4Parser.swift`
- `FMOc/Features/APRS/DeterministicCBOR.swift`
- `FMOc/Features/APRS/FMOV4TrustMaterial.swift`
- `FMOc/Features/APRS/FMOV4CRL.swift`
- `FMOc/Features/APRS/FMOV4Verifier.swift`
- `FMOc/Features/APRS/FMOV4NetworkStore.swift`
- `FMOc/Features/APRS/FMOV4Favorites.swift`
- `FMOc/Features/APRS/FMOV4StationDirectoryView.swift`
- `FMOc/Features/APRS/FMOV4DetailViews.swift`

## 测试

- 呼号规范化、SSID 边界和 9 字节登录身份。
- 固定 `pass -1` / `u/APFMO4` 登录行及 `unverified` 登录响应。
- CRLF 拆包、粘包、UTF-8、空行和 512 字节边界。
- TNC2 来源、TOCALL、路径和畸形输入。
- 所有公开 FMO V4 消息家族、真实 APRS 位置注释边界、坐标、token 顺序、数值、文本及 Base64url 长度。
- greeting → 登录 → 接收顺序、只发送一次登录，以及坏帧不终止有效流。
- 身份持久化与手动优先级、FMO 呼号继承、前后台暂停/恢复、断线等待重连。
- 无身份 → 身份 Sheet → 保存 → 正在接收的 XCUITest 用户流程；0.4 UI 不出现消息、远控或凭据入口。
- 确定性 CBOR 的规范编码/严格拒绝、官方 Root/Intermediate 验签、`{}`/非法 CRL、人工完整证书链与消息签名、重复帧去重。
- 人工可信快照驱动的地图、目录导航、展开搜索和结果显示 XCUITest；测试数据只存在 DEBUG composition。
- Network.framework 真正的公共网络连接仍需使用用户配置的合法呼号做只读集成验收；自动化测试不得使用伪造身份连接公网。
- PASSCODE 固定向量、验证登录、标准消息/ACK/REJ、重复消息只落库一次但重复 ACK、地址+ID 精确关联、有限重试与后台停止。
