---
last-reviewed: 2026-08-08
---

# 模块：FMO 远程控制

## 目的

在“设备”标签下，通过官方公开的 FMO APRS 远控格式向用户指定的 FMO 发送 `NORMAL / STANDBY / REBOOT`。模块只生成三种固定命令，不复用 ADR-0005 的局域网只读 WebSocket，也不提供任意 APRS 或设备管理命令入口。

远控是单次、有副作用的操作：不自动重试；`REBOOT` 在分配 Counter 和生成签名前先完成危险确认与 LocalAuthentication。

## 公共接口

```swift
enum FmoRemoteAction: String, Sendable {
    case normal = "NORMAL"
    case standby = "STANDBY"
    case reboot = "REBOOT"
}

protocol FmoRemoteControlCounterStoring: Actor {
    func next(for target: TNC2Address, timeSlot: UInt64) -> FmoRemoteControlSequence
}

protocol FmoRemoteSecretStoring: Sendable {
    func load(for target: TNC2Address) async throws -> String?
    func save(_ secret: String, for target: TNC2Address) async throws
    func remove(for target: TNC2Address) async throws
}
```

`FmoRemoteControlModel` 是 SwiftUI 唯一调用入口。界面只传动作、目标和用户输入的 SECRET；Time Slot、Counter、HMAC、Keychain 和原始帧均不进入视图状态或用户文案。

## 内部结构

- `FmoRemoteControlCodec` 根据固定协议计算 `floor(unixSeconds / 60)`，拼接发送方基础呼号、十进制 SSID、`CONTROL`、动作、Time Slot 与 Counter，使用 SECRET 做 HMAC-SHA1，取前 8 字节并编码为 16 位大写十六进制。
- `UserDefaultsFmoRemoteControlCounterStore` 按目标地址隔离状态；同一分钟递增、跨分钟归零，并在返回序列前持久化，避免 App 重启复用 `(T,C)`。
- `KeychainFmoRemoteSecretStore` 按目标完整呼号隔离 12 位 SECRET，使用 `WhenUnlockedThisDeviceOnly`；SECRET 不进入 UserDefaults、SwiftData、源码、测试真实值、截图、日志或诊断。
- `UserDefaultsFmoRemoteTargetStore` 只保存非秘密的上次目标地址。启动时先恢复目标，再从对应 Keychain 项读取 SECRET。
- `LocalDeviceOwnerAuthenticator` 使用 `deviceOwnerAuthentication`；认证取消或失败时不访问 Counter store、不签名、不发送。
- 命令通过 ADR-0006 的隔离 APRS 写会话发送一次。官方材料只公开了 `ACK,CONTROL` 级别的确认，当前仅在回复来源等于目标且消息发给当前身份时确认正在等待的动作，不声称可按 Time Slot/Counter 精确关联。

## 数据与安全边界

```text
用户选择目标 + SECRET
→ SECRET: Keychain / target: UserDefaults
→ REBOOT only: danger dialog → LocalAuthentication
→ atomic (Time Slot, Counter)
→ fixed HMAC command codec
→ isolated verified APRS-IS writer（single send）
→ target-sourced ACK,CONTROL / 6-second unconfirmed result
```

任何失败都不会自动重发。未确认表示 App 没有在等待窗口内取得设备确认，不等同于设备一定没有执行；界面不得提供“一键重试”循环或后台补发。

## 依赖

- CryptoKit：HMAC-SHA1（为兼容公开设备协议，仅用于消息认证）。
- Security.framework：Keychain。
- LocalAuthentication：重启前系统身份确认。
- Foundation/UserDefaults：非秘密目标与原子 Counter 状态。
- APRS 模块：类型化地址、隔离验证写会话。
- 无第三方依赖。

## 关键文件

- `FMOc/Features/RemoteControl/FmoRemoteControlProtocol.swift`
- `FMOc/Features/RemoteControl/FmoRemoteControlModel.swift`
- `FMOc/Features/RemoteControl/FmoRemoteSecretStore.swift`
- `FMOc/Features/RemoteControl/FmoRemoteControlCounterStore.swift`
- `FMOc/Features/RemoteControl/FmoRemoteControlView.swift`

## 测试

- 固定 HMAC 与完整命令帧向量。
- Time Slot、同分钟递增、跨分钟归零与重启恢复。
- 非法目标和 SECRET 失败关闭。
- LocalAuthentication 失败不消耗 Counter、不发送命令。
- 三种动作单次发送、目标来源 ACK 和超时未确认。
- 用户已完成 `NORMAL → STANDBY → REBOOT` 分级真机验收；动作结果只按实际设备反馈记录，不由 App 推断。
