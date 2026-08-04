---
last-reviewed: 2026-08-04
---

# 产品规格

## 愿景

让 iPhone 成为 FMO 盒子的可靠原生伴侣：在局域网内自动发现设备并同步位置，在互联网侧安全查看 FMO/APRS 网络、发送标准消息与远控命令、管理通联日志和自建服务器，同时保持设备身份与未公开语音协议的安全边界。

## 用户画像

- **主要用户：** 已取得业余无线电操作证、呼号，并持有已激活 FMO 盒子的 iPhone 用户。
- **服务器管理员：** 自行部署 EMQX 与 FMO SAS，希望移动查看服务状态的用户。
- **移动/车载用户：** 将手机与 FMO 接入同一普通 Wi-Fi 或便携路由器，需要持续同步位置的用户。

## 功能需求

### 局域网设备

#### SPEC-001：发现 FMO 盒子

**优先级：** Must
**状态：** Approved

App 应使用 Bonjour 浏览 `_http._tcp.local.`，识别 FMO 服务并解析可连接地址，同时提供手动主机名/IP 作为回退。

**验收标准：**

- [ ] 同一普通 Wi-Fi 中存在 FMO 时，用户可在 10 秒内看到发现结果或明确的超时状态。
- [ ] 自动发现失败时，用户可输入 `fmo.local` 或 IPv4 地址继续。
- [ ] App 记住用户选定的设备，但不保存 Wi-Fi 密码。
- [ ] 再次自动发现时，App 保留用户手动输入和已经保存的端点，并按稳定的主机与端口身份去重。
- [ ] 用户可移除设备；若移除当前设备，App 同时断开连接并清除保存记录，仍在附近的设备可在后续发现中重新出现。
- [ ] 本地网络权限被拒绝时，App 解释原因并提供系统设置入口。

#### SPEC-002：连接诊断

**优先级：** Must
**状态：** Approved

App 应分别诊断主机解析、HTTP 后台和 GEO WebSocket，并显示可行动的错误。

**验收标准：**

- [ ] 用户能区分未连接 Wi-Fi、无法解析主机、HTTP 不可达、WebSocket 握手失败和响应超时。
- [ ] 诊断明确区分 App 当前会话连接状态与独立可达性探测；探测全部通过不得被表述为首页已建立连接。
- [ ] 诊断报告默认脱敏，不包含精确位置、PASSCODE、SECRET 或服务器令牌。

#### SPEC-003：读取与写入坐标

**优先级：** Must
**状态：** Approved

App 应通过 `ws://<host>/ws` 实现 `getCordinate` 与 `setCordinate`，保留协议历史拼写。

**验收标准：**

- [ ] 能解析 `getCordinateResponse` 并显示盒子坐标。
- [ ] 能获取 iPhone WGS84 坐标并发送 `setCordinate`。
- [ ] 经度、纬度越界时在发送前拒绝。
- [ ] 成功、设备拒绝、连接错误和 5 秒响应超时具有不同结果。

#### SPEC-004：后台位置同步

**优先级：** Must
**状态：** Approved

App 应提供手动、低功耗和车载定位模式。后台发送由 Core Location 事件触发，再应用时间与距离阈值，不承诺严格周期。

**验收标准：**

- [ ] 用户明确选择模式并理解耗电差异。
- [ ] App 离开盒子局域网后暂停发送，不进行高频失败重试。
- [ ] 恢复局域网后可重新连接并继续同步。
- [ ] App 清楚显示后台定位授权和最后一次同步结果。

#### SPEC-005：官方 Web 后台入口

**优先级：** Should
**状态：** Approved

App 应在受限 WebView 或系统浏览器打开盒子官方后台及 QSO 页面，不注入脚本模拟未公开接口。

### APRS 网络

#### SPEC-006：FMO V4 地图与台站目录

**优先级：** Must
**状态：** Approved

App 应展示通过 FMO V4 APRS 获得的用户、BEACON 与 STATION 信息，包括位置、呼号、服务器地址、覆盖范围、在线/峰值人数和数据年龄。

#### SPEC-007：事件时间线与通知

**优先级：** Should
**状态：** Approved

App 应支持 `CQ`、`OMCQ`、`VOCAL`、`ONLINE`、`BEACON`、`STATION` 与 `JOINT + EVENT`，并允许按类型、呼号、距离和收藏过滤。

#### SPEC-008：FMO V4 身份验证

**优先级：** Must
**状态：** Approved

App 应验证 CERT blob、呼号绑定、证书链、证书有效期、Ed25519 消息签名、timeSalt 窗口、JOINT/EVENT 哈希关系和可用 CRL。

**验收标准：**

- [ ] 无法验证的数据不得显示为“可信”。
- [ ] 过期、吊销、签名错误、呼号不匹配和未知根具有不同状态。
- [ ] 不通过降低验证强度来兼容错误报文。

#### SPEC-009：APRS 短消息

**优先级：** Should
**状态：** Approved

用户可配置自己的呼号、SSID 和 APRS PASSCODE，发送/接收标准 APRS 消息与 ACK。凭据必须保存到 Keychain。

#### SPEC-010：FMO 远程控制

**优先级：** Must
**状态：** Approved

App 应按官方示例生成 `NORMAL`、`STANDBY`、`REBOOT`，实现 Time Slot、Counter、HMAC-SHA1 截断签名和 ACK 等待。

**验收标准：**

- [ ] 远控 SECRET 和 PASSCODE 不写入日志或服务器。
- [ ] `REBOOT` 必须经过 LocalAuthentication 二次确认。
- [ ] Counter 在同一 Time Slot 内单调递增并持久化，避免 App 重启后重放。

### QSO 与服务器

#### SPEC-011：QSO 导入、查询与 ADIF

**优先级：** Should
**状态：** Approved

App 应读取用户从 `qso.html` 主动下载的 SQLite 数据库，支持查询、地图、SHA-256 完整性、ECDSA P-256 验签与 ADIF 导出。

#### SPEC-012：自建服务器运维

**优先级：** Could
**状态：** Approved

App 应通过独立 HTTPS API 查看自建服务器的 DNS、MQTT 可达性、EMQX/SAS 状态、连接数、资源使用、广播状态和脱敏日志。写操作必须单独授权并二次确认。

#### SPEC-013：iOS 系统集成

**优先级：** Could
**状态：** Approved

支持 APNs、本地通知、桌面/锁屏小组件、Siri 快捷指令、深色模式、动态字体和 VoiceOver。

## 明确排除

- 解码或收发 FMO MQTT 语音。
- 模拟盒子登录 MQTT。
- 获取、导出、复制或使用盒子私钥。
- 逆向未公开的盒子配置、服务器切换、音量、频率、编码器或 OTA 接口。
- App 内完成官方设备激活或证书签发。
- 将 iPhone 个人热点拓扑列为保证能力，除非实机验证通过。
