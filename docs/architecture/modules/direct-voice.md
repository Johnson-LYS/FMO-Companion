---
last-reviewed: 2026-08-23
---

# 模块：App 直连语音

## 目的

让“FMO 助手（App 直连）”作为独立的软件 FMO 语音终端，在 App 前台通过用户配置的 MQTT 服务器接收 `FMO/RAW`，并仅在用户持续按住 PTT 时采集和发送语音。模块遵守 ADR-0011：使用 App 自有 Ed25519 私钥、User Certificate 和软件 vendor，不读取、导入或复用 FMO 盒子私钥。

## 首版交付范围

- 设备选择器统一展示 App 直连终端和网络 FMO；选择网络 FMO 后隐藏 App 身份、服务器和 PTT。
- 首页与 App 直连横屏卡片共享 `DirectVoiceSessionModel` 和可收回右侧的 `SidePTTControl`；展开后显示大号“按住发射”按钮。
- 前台 MQTT 3.1.1 连接、`FMO/RAW` QoS 0 订阅/发布、单路半双工仲裁、Opus 收发和 AVFoundation 播放/采集。
- App 进入非 active 状态、切换网络 FMO、松手、连接结束、路由抢占或达到 60 秒时停止发射，不补发旧音频。
- 身份申请只导出公钥；私钥 seed 与稳定安装后缀存放在独立 Keychain 命名空间。导入时验证 Root、Intermediate、User Certificate 的 Ed25519 签名、有效期、issuer、UID 范围和本机公钥绑定。
- 语音服务器页优先展示当前 FMO 网络快照中经过完整证书验证的 STATION；选择后从该服务器证书自动生成 UID、呼号、TBS SHA-256 指纹、主机和端口，手动配置只作为高级回退。

首版不承诺后台 MQTT 常驻、PushToTalk framework/APNs、独立于 APRS STATION 的服务器发现、断线退避重连、CRL 客户端刷新、网络抖动缓冲或真实服务器互通验收。这些仍按计划 0010 的后续门槛推进，不能把当前模拟器/离线测试表述为真机射频闭环。

## 公共边界

```swift
protocol DirectVoiceIdentityProviding: Sendable {
    func currentIdentity(now: Date) async throws -> DirectVoiceIdentity
    func sign(_ data: Data) async throws -> Data
    func installationSuffix() async throws -> String
}

protocol FMOMQTTTransport: Sendable {
    func connect(_ request: FMOMQTTConnectRequest) async throws
    func incomingRaw() async throws -> AsyncThrowingStream<Data, Error>
    func publishRaw(_ payload: Data) async throws
    func disconnect() async
}

protocol FMOAudioCodec: Sendable {
    func encode40ms(_ pcm: [Int16]) async throws -> Data
    func decode40ms(_ data: Data) async throws -> [Int16]
    func concealLoss() async throws -> [Int16]
    func reset() async throws
}
```

SwiftUI 只依赖 `DirectVoiceSessionModel` 的身份、服务器 Profile、会话快照、终端选择和 PTT 意图，不接触 Keychain seed、MQTT client、Opus 指针或原始语音字节。

## 内部结构

- `KeychainDirectVoiceIdentityProvider`：生成 `ThisDeviceOnly` Ed25519 seed，验证并保存证书元数据，按需签名 SAS proof；MQTT 与 UI 无法读取 seed。
- `SASAuthPayloadBuilder`：为每次 CONNECT 构造 User TBS 指纹、12 元确定性 CBOR proof 和无 padding Base64url JSON password；TLS SNI 使用鉴权目标域名。
- `MQTTNIOFMOMQTTTransport`：封装 mqtt-nio 2.13.0，在 iOS 使用 `NIOTSEventLoopGroup.singleton` 对接 Network.framework，只允许 `FMO/RAW`、QoS 0、clean session 和不超过 1400 字节的 payload；不得传入 iOS 上无法创建 bootstrap 的 POSIX `MultiThreadedEventLoopGroup`。
- `FMORawParser` / `FMORawEncoder`：固定 64 字节头、小端序、嵌套长度、连续 frame index、帧区 IEEE CRC32、软件 vendor `0x2000` 和尾随字节拒绝。
- `LibOpusCodec`：官方 libopus 1.6.1 XCFramework，经最小 C bridge 固定 8 kHz、单声道、VOIP、complexity 4、VOICE、VBR、constrained VBR 和最大带宽参数；每帧 320 样本/40 ms。
- `FMOVoiceRouteArbiter`：1500 ms 占用窗口、较早流抢占和同起点较小 UID 决胜；只把当前获胜流交给解码器。
- `DirectVoiceSession`：Actor 隔离 MQTT、路由、编码缓存和状态；发送同时受五帧/200 ms 与 1400 字节限制，释放 PTT 立即发送尾包。
- `DirectVoiceAudioEngine`：在 MainActor 上管理 AVAudioSession、AVAudioConverter、麦克风 tap 和播放节点；PCM 不离开实时内存。

## 数据与生命周期

```text
App public key → administrator-issued certificate bundle → verified metadata + Keychain seed
verified STATION certificate → server profile + fresh timestamp → SAS proof → MQTT CONNECT → FMO/RAW subscription
incoming RAW → strict parse + CRC → route arbiter → Opus decode → 8 kHz playback
hold PTT → microphone → 8 kHz Int16 → Opus → RAW/CRC → QoS 0 publish
release / inactive / switch terminal / disconnect / 60 s → stop capture + flush or discard bounded state
```

`ContentView` 持有唯一 `DirectVoiceSessionModel`。首页和横屏只改变投影，不创建第二条 MQTT 或音频会话。选择 App 直连后，盒子管理入口、坐标、诊断和本地 `/audio` 投影隐藏；选择网络 FMO 时 App PTT 收起并停止 Direct Voice。

实体 FMO 的 ADR-0010 目录只有服务器 UID 和名称，不能提供 SAS proof 所需的服务器证书呼号与指纹，因此不得直接转成 `FMOServerProfile`。App 直连选择器只消费 `FMOV4NetworkStore` 验签后保留的 STATION 服务器身份；端口 `8883` 按 TLS 连接，其余端口按明文连接并显示风险状态。经过验签的完整 Profile 按 UID 保存为 Direct Voice 独立目录，后续同 UID 广播刷新字段；该目录只缓存公开鉴权元数据，不表示服务器当前在线，也不等同于公共服务器收藏。所选 Profile 另行持久化，之后不依赖该 STATION 继续在线。

## 依赖、许可与复现

- mqtt-nio 精确固定为 2.13.0，revision 记录在 `Package.resolved`，Apache-2.0。
- libopus 固定官方 `v1.6.1`，BSD 许可保存在 `FMOc/Vendor/Opus/COPYING`。
- `scripts/build-opus-xcframework.sh` 可重建 iOS arm64 与 Simulator arm64/x86_64、最低 iOS 26.0 的 XCFramework，并链接项目内最小配置 bridge。
- 当前二进制 SHA-256：device `109493f0dab999ff7d5219e02a80e612e70bdcdc484e56ccc236e8e4e9a1399f`；simulator `ab42a077ad56226a45ab7541aa09a77591745f319f04e647397fedb3e35e2172`。

## 隐私与失败规则

麦克风 PCM、接收 PCM、Opus 和 FMO/RAW 不进入文件、UserDefaults、日志、分析、崩溃附件或测试 fixture。明文 MQTT Profile 显示风险提示；TLS 不关闭系统证书和主机名验证。畸形、超长、CRC 错误、未知 codec 或非当前路由 payload 均丢弃，不做宽松猜测。

## 关键文件与测试

- `FMOc/Features/Voice/Identity/DirectVoiceIdentity.swift`
- `FMOc/Features/Voice/Authentication/DirectVoiceAuthentication.swift`
- `FMOc/Features/Voice/Protocol/FMORawPacket.swift`
- `FMOc/Features/Voice/Transport/FMOMQTTTransport.swift`
- `FMOc/Features/Voice/Codec/LibOpusCodec.swift`
- `FMOc/Features/Voice/Session/DirectVoiceSession.swift`
- `FMOc/Features/Voice/UI/SidePTTControl.swift`
- `FMOcTests/Voice/`
- `FMOcUITests/FMOcUITests.swift`

自动化覆盖有效 App 证书链与 Keychain 公钥绑定、SAS password、FMO/RAW 往返和 CRC、仲裁、Opus 40 ms 往返、五帧 PTT 发布，以及首页/横屏共享侧边 PTT。真实 iPhone、真实 SAS/EMQX 和任何可能触发射频发射的验收仍需用户在受控环境明确执行。
