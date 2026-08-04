---
last-reviewed: 2026-08-04
status: active
---

# 计划 0003：产品路线图

| 版本 | 主题 | 主要交付 | 状态 |
|---|---|---|---|
| 0.1 | 局域网闭环 | 发现、诊断、GEO 读写、手动定位 | Complete |
| 0.2 | 可靠定位 | 低功耗/车载模式、重连、后台权限、官方 Web 后台入口 | Planned |
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

## 0.4 FMO APRS

- CQ、OMCQ、VOCAL、ONLINE、BEACON、STATION、JOINT/EVENT。
- 确定性 CBOR、CERT blob、Ed25519、timeSalt、CRL。
- 地图、列表、搜索、收藏和数据年龄。
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
