---
last-reviewed: 2026-08-04
status: active
---

# 计划 0003：产品路线图

| 版本 | 主题 | 主要交付 | 状态 |
|---|---|---|---|
| 0.1 | 局域网闭环 | 发现、诊断、GEO 读写、手动定位 | Complete |
| 0.2 | 可靠定位 | 低功耗/车载模式、重连、后台权限、官方 Web 后台入口 | Complete |
| 0.3 | 设备仪表盘基础 | 共享快照、GEO/Maidenhead、局部降级与最终交互原型 | In Progress |
| 0.4 | FMO APRS | V4 解析、证书链、签名/CRL、地图、服务器目录、事件流 | Planned |
| 0.6 | 通讯与远控 | APRS 短消息、ACK、NORMAL/STANDBY/REBOOT、Keychain | Planned |
| 0.8 | QSO | SQLite 导入、查询、P-256 验签、ADIF 导出 | Planned |
| 1.0 | 完整伴侣 | 自建服务器 API、APNs、小组件、快捷指令、可访问性 | Planned |

## 0.2 可靠定位

- 手动、低功耗、车载三种模式。
- 基于 Core Location 事件的时间/距离节流。
- 网络离开与恢复。
- 管理后台和 QSO Web 页面入口。
- 不承诺严格分钟周期。

## 0.3 设备仪表盘基础与最终交互原型

- 完整 HTML 原型已经用户确认，继续作为最终首页和锁屏信息架构，不代表所有字段当前都有数据源。
- 先实现共享状态模型、字段来源/时间/过期语义、局部降级，以及现有 GEO 能力真实支持的连接与 Maidenhead 字段。
- 呼号、服务器、过滤距离、QSO、TX/RX、延迟、管理员、在线/最大在线和实时讲话等无正式来源字段标记为 `Deferred — external contract`，待公开接口出现后逐项接入。
- 同一类型化快照驱动首页与锁屏；每个字段保留来源、观测时间、可信度和过期状态。
- 锁屏实时活动只投影当前确有可信来源的高价值字段；信息不足以形成有用体验时可延后增强，不用示例值填充。
- 0.3 不前移完整 APRS-IS、QSO 导入或 APNs，也不把这些来源的“最后观测”冒充设备内部实时状态。

## 0.4 FMO APRS

- CQ、OMCQ、VOCAL、ONLINE、BEACON、STATION、JOINT/EVENT。
- 确定性 CBOR、CERT blob、Ed25519、timeSalt、CRL。
- 地图、列表、搜索、收藏呼号/公共服务器、收藏事件过滤和数据年龄。
- 后台通知架构需要在直接 APRS-IS 与自建推送服务间做 ADR。

## 0.6 通讯与远控

- 标准 APRS 消息与 ACK。
- 用户显式配置 PASSCODE。
- NORMAL、STANDBY、REBOOT。
- HMAC、Counter、Time Slot、Keychain 与危险操作二次确认。

## 0.8 QSO

- 用户主动从 `qso.html` 下载或 Files 导入。
- SQLite schema 检查和查询。
- SHA-256 与 ECDSA P-256 验签。
- ADIF 与 `APP_FMO_*` 字段。

## 1.0 完整伴侣

- `api.fmo.bi8syn.com` 或最终确定域名下的 HTTPS API。
- EMQX/SAS/主机状态、告警和脱敏日志。
- APNs、本地通知、小组件、快捷指令。
- VoiceOver、动态字体、隐私清单、发布准备。

## 持续边界

以下项目除非出现正式公开协议或 SDK，否则不排期：FMO 语音收发、盒子私钥、模拟设备身份、原生映射未公开设置、自动设备激活和证书签发。
