---
last-reviewed: 2026-08-06
---

# FMO 已公开能力与来源

本文件是产品范围的证据索引，不保存用户凭据、设备私钥或真实 QSO 数据。

## 能力矩阵

| 能力 | 公开依据 | App 结论 |
|---|---|---|
| Bonjour 发现 FMO | Android GPS 工具浏览 `_http._tcp.local.` 并匹配 `fmo` | 可原生实现 |
| GEO 坐标读写 | `ws://host/ws`；`getCordinate` / `setCordinate` JSON | 可原生实现 |
| 设备综合状态 API | 官方说明书描述屏幕字段；2026-08-05 用户授权分析其本人设备后台抓包，观察到 `/ws` 与 `/events` 管理消息，但仍无公开版本契约 | `User-authorized read-only — ADR-0005`；只允许固定白名单、脱敏 schema 和局部降级 |
| 官方管理后台 | 使用说明书确认同局域网访问 `fmo.local` | 可在 App 打开，不映射未知 API |
| APRS FMO V4 | 官方报文格式公开 CQ、OMCQ、VOCAL、ONLINE、BEACON、STATION、JOINT/EVENT；VOCAL 由 PTT ≥ 3 秒触发并携带呼号、位置与 serverUID，但没有会话目标或结束状态 | 可解析、展示与验证；VOCAL 只表述为最近语音活动 |
| FMO V4 信任验证 | CERT CBOR、Ed25519、timeSalt、根/中间证书与 CRL | 可原生实现 |
| APRS 远控 | 官方示例公开 NORMAL、STANDBY、REBOOT、HMAC、Counter、ACK | 可原生实现 |
| QSO 数据 | Web UI 备份 SQLite，官方脚本读取 `qso_logs` 并导出 ADIF | 可由用户导入处理 |
| QSO 验签 | 官方工具公开 SHA-256 + ECDSA P-256 验证 | 可用 CryptoKit 实现 |
| 自建服务器状态 | 用户控制 EMQX/SAS/主机 | 通过自建 HTTPS API 实现 |
| MQTT 语音客户端 | 完整语音帧、编码器和设备客户端 SDK 未公开 | 不实现 |
| 设备私钥 | 身份安全依赖设备持有私钥 | 不提取、不复制、不模拟 |

## 本地管理 WebSocket 观察记录

以下结论来自用户本人设备与后台页面的局域网抓包，只用于需求和协议风险评估。原始抓包包含精确位置、网络端点、证书指纹及 PASSCODE 等敏感信息，不进入仓库、测试 fixture、日志、截图或诊断导出。

| 端点/消息 | 已观察字段或行为 | 证据状态 |
|---|---|---|
| `/ws` `user/getInfo` | 呼号；同一响应还包含不应进入 Dashboard 的证书指纹、MQTT 端点与局域网 IP | ADR-0005 白名单；只解码呼号 |
| `/ws` `station/getCurrent` | 当前服务器名称与 UID；完整观察 A → B → A 切换后的重新读取 | ADR-0005 白名单；0.3 连接期间可低频重新读取，不包含切换写操作 |
| `/ws` `config/getServerFilter` | 枚举 `0...7`：禁用、50、100、200、500、1000、2000、5000 km | ADR-0005 白名单；未知值拒绝 |
| `/ws` `config/getUserPhyFreq` | 单一工作频率 | ADR-0005 白名单；不得拆成 TX/RX |
| `/ws` `qso/getList` | 日志总数与分页日志条目 | ADR-0005 只请求第 0 页 20 条且只解码 `count`；不是实时通联数 |
| `/events` `qso/callsign` | 当前讲话状态、呼号、可选网格、连接内 `seq/ts` | ADR-0005 白名单；与 APRS `VOCAL` 分离 |
| `/events` `qso/history` | 最近最多 20 条呼号与 `utcTime` | ADR-0005 白名单；不是完整 QSO 数据库或 0.4 APRS 事件流 |
| `/ws` 配置与控制写操作 | 官方 Web UI 可在局域网内配置盒子，用户授权样本中观察到多种写入行为，但没有公开版本、鉴权或错误契约 | ADR-0005 明确排除；App 继续打开官方 Web UI，不实现、枚举或代理观察到的写命令 |
| `/audio` | 存在独立 WebSocket 端点 | 明确排除；不分析、不实现 |

握手样本未出现 Cookie、Authorization、TLS 或 WebSocket 子协议，而 `/ws` 同时存在读取 PASSCODE 的命令。若未来获准接入，必须使用只读命令与字段双重白名单，不得实现通用命令代理，不得请求、解码、保存或记录 PASSCODE，并为原始帧大小、畸形数据、未知字段和秘密字段丢弃建立测试。

### 待补样本

- 当前服务器不可达、恢复和 WebSocket 重连；“无服务器”不是已确认的正常切换状态。
- `isHost: true` 的讲话事件；取得前不显示或推断管理员/主机角色。
- FMO 重启后 `/events` 的 `seq/ts` 行为；取得前只保证单次 WebSocket 会话内排序。
- 服务器管理员呼号、当前/最大在线人数仍无本地接口证据。
- 延迟没有可靠数据源，0.3 首页隐藏；实时活动已移出 0.3。

## 官方资料

- [FMO 使用说明书](https://bg5esn.com/docs/fmo-usage/)
- [FMO Android GPS Tool（0.1 协议基线 commit）](https://github.com/BG5ESN/FMO-Andorid-GPS-Tool/tree/42d4c9271043a8fe5ec42119d9f4469d8d89b5fb)
- [FMO 4.0 APRS 报文格式](https://bg5esn.com/docs/fmo-aprs-formate/)
- [FMO APRS Remote Control Tool](https://github.com/BG5ESN/FMO-APRS-Remote-Control-Tool)
- [FMO SQLite → ADIF](https://github.com/BG5ESN/FMO-sqlite-2-adif)
- [FMO 日志签名验证工具](https://github.com/BG5ESN/fmo-log-sign-verify-tool)
- [FMO Server Authorizer Service](https://github.com/BG5ESN/fmo-server-authrozier-service)
- [FMO 关于开源的思考](https://bg5esn.com/docs/fmo-open-source-announcement/)

## Apple 平台资料

- [Creating an Xcode project for an app](https://developer.apple.com/documentation/xcode/creating-an-xcode-project-for-an-app/)
- [Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)

## 变更规则

新增 FMO 功能前必须先找到官方文档、官方仓库、接口所有者明确授权或经用户明确授权并由 ADR 固定最小边界，同时在此处记录。仅凭 UI 现象、抓包结果或第三方推测只能标记为 `Observed — authorization pending`，不能进入 Release 数据源。
