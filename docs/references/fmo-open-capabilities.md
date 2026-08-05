---
last-reviewed: 2026-08-04
---

# FMO 已公开能力与来源

本文件是产品范围的证据索引，不保存用户凭据、设备私钥或真实 QSO 数据。

## 能力矩阵

| 能力 | 公开依据 | App 结论 |
|---|---|---|
| Bonjour 发现 FMO | Android GPS 工具浏览 `_http._tcp.local.` 并匹配 `fmo` | 可原生实现 |
| GEO 坐标读写 | `ws://host/ws`；`getCordinate` / `setCordinate` JSON | 可原生实现 |
| 设备综合状态 API | 官方说明书描述屏幕字段，但截至 2026-08-04 未公开状态端点、字段 schema、鉴权、错误或版本契约；官方 GEO 工具仅公开坐标消息 | 保留最终设计；除 GEO 坐标派生字段外逐项延期，不探测或依赖未公开接口 |
| 官方管理后台 | 使用说明书确认同局域网访问 `fmo.local` | 可在 App 打开，不映射未知 API |
| APRS FMO V4 | 官方报文格式公开 CQ、OMCQ、VOCAL、ONLINE、BEACON、STATION、JOINT/EVENT；VOCAL 由 PTT ≥ 3 秒触发并携带呼号、位置与 serverUID，但没有会话目标或结束状态 | 可解析、展示与验证；VOCAL 只表述为最近语音活动 |
| FMO V4 信任验证 | CERT CBOR、Ed25519、timeSalt、根/中间证书与 CRL | 可原生实现 |
| APRS 远控 | 官方示例公开 NORMAL、STANDBY、REBOOT、HMAC、Counter、ACK | 可原生实现 |
| QSO 数据 | Web UI 备份 SQLite，官方脚本读取 `qso_logs` 并导出 ADIF | 可由用户导入处理 |
| QSO 验签 | 官方工具公开 SHA-256 + ECDSA P-256 验证 | 可用 CryptoKit 实现 |
| 自建服务器状态 | 用户控制 EMQX/SAS/主机 | 通过自建 HTTPS API 实现 |
| MQTT 语音客户端 | 完整语音帧、编码器和设备客户端 SDK 未公开 | 不实现 |
| 设备私钥 | 身份安全依赖设备持有私钥 | 不提取、不复制、不模拟 |

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

新增 FMO 功能前必须先找到官方文档、官方仓库或明确授权的接口，并在此处记录。仅凭 UI 现象、抓包结果或第三方推测不能把功能标记为“确定可实现”。
