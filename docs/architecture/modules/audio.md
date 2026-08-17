---
last-reviewed: 2026-08-17
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

`ContentView` 为当前设备持有唯一 `FmoAudioMonitorModel`。连接随当前 FMO 连接存在，不以 `scenePhase` 作为会话身份；首页、横屏及前后台切换消费同一实例，所以不会重连 `/audio`，也不会改变声音开关。`audioSessionID` 对应的 SwiftUI `.task(id:)` 直接等待 `FmoAudioSessionCoordinator`，不再派生脱离结构化取消的子任务；旧端点或旧连接状态任务被取消后，不能延迟执行 `stop()` 并关闭替代会话。音频 WebSocket 首次失败、短暂断开或自然结束时，模型暂停播放器并以可取消的一秒间隔自动重建流；这种瞬时恢复保留用户的声音开关，收到新帧后继续波形与播放。握手按官方本地页面设置与当前端点匹配的 HTTP `Origin`，不硬编码设备地址。首次连接和切换设备默认静音；临时断线及前后台切换保留选择。静音期间的帧不会缓存供稍后回放。音频会话自身产生的 category route change 不关闭声音，只有系统中断开始或旧输出设备移除才静音。

工程声明 `UIBackgroundModes = audio, location`。用户打开声音时立即启动 `.playback + .spokenAudio` 连续接收播放链，不等待第一帧才准备音频会话；无人讲话时输出自然空闲，后续 PCM 到达即可直接播放。Audio 后台模式承担锁屏/切换 App 后的持续可听监听；关闭声音会立即停用播放器，不另行生成静音媒体保活。设备 WebSocket 不因进后台主动断开，因此返回 App 时 Dashboard 保持连接态；但静音时 iOS 可挂起进程，系统中断、网络变化和资源回收也可能结束连接，恢复仍依赖各客户端既有重连逻辑。

## 依赖与边界

- Foundation / URLSession：WebSocket 与取消感知流。
- AVFoundation：用户显式开启后的 `.playback + .spokenAudio` 本地及后台播放；不申请麦克风权限，也不启用仅适用于录音类别的 HFP 输入选项。
- Device 的 `FmoDeviceEndpoint`：唯一端点来源，不硬编码主机或端口。
- Dashboard：只消费类型化模型；Audio 不读取 Dashboard 讲话状态，Dashboard 不解析 PCM。
- 无第三方依赖。

原始 PCM、波形点和音频派生内容不进入持久化、日志、诊断、分析、崩溃上下文、截图或 fixture。格式不匹配时不探测编码器或其他协议变体。

## 关键文件

- `FMOc/Features/Audio/FmoLocalAudioProtocol.swift`
- `FMOc/Features/Audio/FmoLocalAudioClient.swift`
- `FMOc/Features/Audio/FmoAudioMonitorModel.swift`
- `FMOc/Features/Audio/FmoAudioSessionCoordinator.swift`
- `FMOc/ContentView.swift`
- `FMOc/Features/Dashboard/DeviceDashboardSummaryView.swift`
- `FMOc/Features/Dashboard/DashboardFullscreenView.swift`

## 测试

- Int16 little-endian 正负边界、固定帧长和 0.28 秒帧时长。
- 波形点数、归一化范围和静音时持续更新。
- 精确 `p` 保活忽略；未知文本、消息类型和错误长度失败关闭。
- URL 与对应 HTTP `Origin` 只由所选设备端点构造。
- 默认静音、新帧播放、瞬时断流自动重连且保持声音开关、临时停止不重置选择、显式结束重置选择与有界缓冲；会话协调测试覆盖取消的旧状态任务不能停止替代会话，握手测试覆盖官方页面同源头，事件策略测试覆盖 category change 不误静音。
- iPhone 真机验收：首页默认无声，任一喇叭按钮开启/关闭均即时生效；进入与退出横屏、锁屏及切换其他 App 时状态和播放连续，返回 App 不出现主动重连卡片。
