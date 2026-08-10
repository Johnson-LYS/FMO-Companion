---
last-reviewed: 2026-08-07
---

# APRS 消息与 FMO 远控协议基线

## 固定资料

- APRS 消息：APRS Protocol Reference 1.0.1，Chapter 14，官方 PDF `https://www.aprs.org/doc/APRS101.PDF`。
- APRS-IS 登录：APRS-IS Connecting 页面 `https://www.aprs-is.net/Connecting.aspx`。
- PASSCODE 交叉实现：aprsc `bfc2090568aa53278c57da6af0ff860db5c0d8a4` 的 `src/passcode.c`。仅用来交叉验证公开算法，生产实现为独立 Swift 代码。
- FMO 远控：BG5ESN/FMO-APRS-Remote-Control-Tool `v1.00`，commit `1b3114e9d282f853925b49260facffd3f48e7c9f`。仓库未提供许可证，项目不复制其源码，只根据公开 README 独立实现报文格式。

## 标准消息边界

- 信息字段为 `:<ADDRESSEE_9>:<TEXT>{<ID>`；目标地址右侧补空格至 9 字节。
- APRS 1.0.1 的通用基线是可打印 7-bit ASCII 与最多 67 字节正文；FMO 当前官方消息页面实际把正文限制为 60 UTF-8 字节，并以中文作为合法输入示例。FMO Companion 因此采用更小的 60 字节上限并接收合法 UTF-8，同时拒绝会破坏 APRS-IS 单行边界的控制字符和会与消息 ID 分隔符冲突的 `{`。
- FMO 消息兼容帧使用 `APFMO0` TOCALL；消息 ID 仍使用 1–5 位 ASCII 字母数字。此前首轮实现使用未被目标 FMO 订阅的自定义 `APFMC0`，导致帧虽可写入 APRS-IS，但无法进入 FMO 消息链路。
- ACK/REJ 分别为 `ack<ID>` / `rej<ID>`。重复的带 ID 消息只落库一次，但每次仍发送 ACK。
- 写会话使用按基础呼号计算的 PASSCODE；SSID 不参与计算。接收过滤器使用消息目标过滤，不扩展为任意 APRS 发送器。

FMO 消息页面和本地 `/ws` 的 `message` 路由仅作为兼容行为的只读核对依据；App 的 FMO 网络消息仍使用独立 APRS-IS 会话，不依赖与盒子同一局域网，也不把局域网管理写接口加入 ADR-0005 状态客户端。

## FMO 远控边界

- 报文为 `<FROM>\>APFMO0,TCPIP*::<TARGET_9>:CONTROL,<ACTION>,<T>,<C>,<SIG>`。
- 动作为 `NORMAL / STANDBY / REBOOT`；`T=floor(unixSeconds/60)`；同一分钟内 `C` 单调递增，跨分钟重置为 0，并持久化避免重启复用。
- 签名原文为 `FROM_CALL + FROM_SSID + CONTROL + ACTION + T + C`，不含分隔符；使用 SECRET 作为 UTF-8 key 做 HMAC-SHA1，取前 8 字节并转 16 位大写十六进制。
- SECRET 限 12 位大写 ASCII 字母数字，仅进入 Keychain，不写日志、诊断、文档、UserDefaults 或 SwiftData。
- 官方工具只按 `ACK,CONTROL` 识别回复，未公开可可靠关联动作、Time Slot 和 Counter 的 ACK 结构。因此 0.6 首版只把来源与目标均匹配的控制 ACK 视为设备确认，不声称具备更细粒度的精确关联。

## 冻结向量

- PASSCODE：`N0CALL → 13023`，`ZZ0TST → 19128`，`BG5ESN / BG5ESN-10 → 22446`。
- 远控：source `BG5ESN-10`、target `BD7XYZ-1`、action `STANDBY`、T `30000000`、C `2`、SECRET（测试专用）`ABCDEF123456`，签名为 `3DFD67625F675096`。

这些向量只包含公开或人工生成数据，不包含真实 PASSCODE、SECRET、位置或用户消息。
