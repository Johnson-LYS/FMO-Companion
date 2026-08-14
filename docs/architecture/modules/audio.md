---
last-reviewed: 2026-08-14
---

# 模块：本地接收音频

## 目的

在用户选中的 FMO 与 iPhone 位于可达局域网时，为设备首页和横屏仪表盘提供共享的瞬时音频状态，以及用户显式开启的本机播放。模块只实现 ADR-0009 固定的只接收 PCM 契约，不录制、不保存、不上传、不转发，也不参与当前讲话者判定。

## 公共接口

```swift
protocol FmoLocalAudioStreaming: Sendable {
    func frames(from endpoint: FmoDeviceEndpoint) async
        -> AsyncThrowingStream<FmoPCMFrame, any Error>
    func disconnect() async
}

struct FmoPCMFrame: Sendable {
    static let sampleRate = 8_000.0
    static let channelCount = 1
    static let byteCount = 4_480
    static let sampleCount = 2_240
    let samples: [Int16]
}
```

`FmoAudioMonitorModel` 是 SwiftUI 的唯一消费入口。视图读取有界波形、接收状态和声音开关，不接触 WebSocket 消息或 PCM 字节。

## 内部结构

- `FmoLocalAudioClient` 从当前 `FmoDeviceEndpoint` 构造 `/audio` URL，建立独立 `URLSessionWebSocketTask`。
- `FmoLocalAudioProtocol` 只接受 4480 字节二进制消息，并按 8 kHz、signed Int16 little-endian、单声道解码；精确文本 `p` 被忽略，其他消息失败关闭。
- `FmoAudioMonitorModel` 保留当前与上一帧的有界 PCM 可视化缓冲；视图使用系统动画时钟按 8 kHz 采样游标取得 40 ms 时域窗口，以固定 2.2 倍有界显示增益在画布上原地重绘 128 点波形，不把约 3.57 Hz 的网络包到达频率暴露为 UI 刷新率。帧超过正常时长且度过 40 ms 抖动宽限后，最后窗口在 180 ms 内平滑衰减至零线。显示增益不进入播放链路；声音关闭时仍更新波形，开启后只把新帧交给播放器。
- `AVFoundationFmoAudioPlayer` 使用 8 kHz Int16 固定格式与最多三个待播放缓冲。关闭声音或结束会话时立即停止引擎并释放音频会话。
- `AsyncThrowingStream` 只保留最新四帧；消费落后时丢弃旧帧，不让内存或播放延迟持续增长。

## 数据与生命周期

```text
selected FmoDeviceEndpoint
→ ws://<selected-device>/audio
→ fixed message allowlist
→ FmoPCMFrame
├→ current + previous bounded PCM frames
│  → 8 kHz display cursor → 40 ms / 128-point oscilloscope → DashboardFullscreenView
└→ user enabled only → AVAudioEngine → local speaker
```

`ContentView` 为当前设备持有唯一 `FmoAudioMonitorModel`。连接只在 App active 且当前 FMO 已连接时存在；首页和横屏消费同一实例，所以 Hero 转场、自然旋转和退出全屏既不重连 `/audio`，也不改变声音开关。音频 WebSocket 首次失败、短暂断开或自然结束时，模型暂停播放器并以可取消的一秒间隔自动重建流；这种瞬时恢复保留用户的声音开关，收到新帧后继续波形与播放。首次连接默认静音；后台、设备断线或设备变化才取消整个会话并恢复静音。静音期间的帧不会缓存供稍后回放。

## 依赖与边界

- Foundation / URLSession：WebSocket 与取消感知流。
- AVFoundation：用户显式开启后的 `.playback + .spokenAudio` 本地播放；不申请麦克风权限，也不启用仅适用于录音类别的 HFP 输入选项。
- Device 的 `FmoDeviceEndpoint`：唯一端点来源，不硬编码主机或端口。
- Dashboard：只消费类型化模型；Audio 不读取 Dashboard 讲话状态，Dashboard 不解析 PCM。
- 无第三方依赖。

原始 PCM、波形点和音频派生内容不进入持久化、日志、诊断、分析、崩溃上下文、截图或 fixture。格式不匹配时不探测编码器或其他协议变体。

## 关键文件

- `FMOc/Features/Audio/FmoLocalAudioProtocol.swift`
- `FMOc/Features/Audio/FmoLocalAudioClient.swift`
- `FMOc/Features/Audio/FmoAudioMonitorModel.swift`
- `FMOc/ContentView.swift`
- `FMOc/Features/Dashboard/DeviceDashboardSummaryView.swift`
- `FMOc/Features/Dashboard/DashboardFullscreenView.swift`

## 测试

- Int16 little-endian 正负边界、固定帧长和 0.28 秒帧时长。
- 波形点数、归一化范围和静音时持续更新。
- 精确 `p` 保活忽略；未知文本、消息类型和错误长度失败关闭。
- URL 只由所选设备端点构造。
- 默认静音、新帧播放、瞬时断流自动重连且保持声音开关、关闭/停止后按钮重置与有界缓冲。
- iPhone 真机验收：首页默认无声，任一喇叭按钮开启/关闭均即时生效；进入与退出横屏时状态和播放连续，后台后停止播放。
