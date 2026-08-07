---
last-reviewed: 2026-08-07
status: in-progress
---

# 计划 0007：里程碑 0.4 FMO APRS

## 目标

在不发送 APRS 数据、不接触设备私钥且不降低 FMO V4 验证强度的前提下，让用户在 App 活跃期间查看可信的 FMO 网络地图、台站与公共服务器目录、完整事件流和收藏。

## 已确认边界

- APRS-IS 使用 `pass -1` 只读登录和用户定义过滤端口 `14580`；只订阅 TOCALL `APFMO4`，不接收完整 APRS 流。
- 只读身份由规范化呼号与独立 App SSID 组成。手动设置优先；没有手动值时继承最近一次可信 FMO 呼号。身份不含 PASSCODE，客户端不得调用盒子的 `getPasscode`。
- APRS-IS 会话只随 App 活跃生命周期运行；0.4 不承诺后台持续接收、本地通知或 APNs。
- 标准 APRS 消息、ACK、位置发送与公网 FMO 远控属于 0.6。公网远控使用公开 APRS-IS 控制格式，不复用局域网 `/ws`。
- 用户授权抓包中观察到的局域网管理写命令继续由官方 Web UI 承担；ADR-0005 本地客户端保持严格只读。
- 只解析公开 `APFMO4`：`CQ`、`OMCQ`、`VOCAL`、`ONLINE`、`BEACON`、`STATION`、`JOINT + EVENT`。消息类与语音内容不进入 0.4。

## 完成定义

1. 用户可自动继承或手动配置只读 APRS 身份，并看到连接、重连、离线和数据新鲜度状态。
2. App 只接收过滤后的 FMO V4 帧；没有任何生产代码路径可以发送 APRS 数据帧。
3. CERT、呼号绑定、证书链、有效期、CRL、消息签名、timeSalt 和 JOINT/EVENT 哈希关系按固定顺序验证。
4. 只有完整验证的数据进入可信地图、目录和事件；失败数据只保留类型化诊断计数，不保存原始帧或敏感内容。
5. 地图、目录、事件流、搜索、呼号收藏和公共服务器收藏与确认原型一致。
6. 网络、解析、验证、聚合、持久化和 UI 投影均通过协议注入与自动化测试隔离。
7. 通用 iOS Simulator 构建、完整单元测试和真实 APRS-IS 只读连接验收通过。

## 实施顺序

### 1. 公开协议与信任材料 checkpoint

**状态（2026-08-06）：Implementation checkpoint resolved。** 官方 SAS 仓库已公开 Root/Intermediate CA、Root/Intermediate CRL 与用户证书的固定顺序 CBOR TBS，并提供与官方内置信任锚一致的实现；Root 自签名与 Intermediate 签名已由 CryptoKit 实测通过。Root CRL 的 `{}` 与 SAS 的 `not published yet` 行为一致，App 将其显示为“暂无已知吊销”；已签名 CRL 过期或不可用时仍保留独立可信状态。详细证据见 `docs/references/fmo-aprs-v4-readiness.md`。

独立证书许可证 URL 与完整官方 APRS CERT/SIG 字节向量仍需在发布前关闭，因此当前实现保留可替换信任材料和测试注入边界；这两项不再阻止开发和用户授权联调，但不得在发布说明中宣称已解决。

- 固定官方 FMO V4 文档版本、APRS-IS 连接规范、根/中间证书和 CRL 来源；核对证书材料许可证及分发方式。
- 从官方示例制作最小、人工化测试向量；不得把真实网络捕获、真实证书指纹、呼号或位置写入仓库。
- 用 spike 验证 CryptoKit Ed25519 与确定性 CBOR 兼容性。当前候选为项目内最小严格 RFC 8949 编解码器，只支持 FMO 所需的无符号整数、字节串、文本与固定长度数组；完整官方向量通过前不写入生产代码、不增加第三方依赖。
- 核对公开 V4 文档与远控示例中消息 TOCALL 的差异；差异不阻塞只读取 `APFMO4`，但必须在 0.6 前关闭。

### 2. 只读身份与 APRS-IS 传输

**状态（2026-08-06）：Implemented。** 已实现身份规范化与持久化优先级、可信本地 FMO 呼号继承、亚洲 Tier 2 端点、Network.framework TCP、固定只读登录、CRLF/512 字节分帧、App 活跃生命周期、15 秒登录超时、取消与 `1...60` 秒有上限退避。身份 Sheet 与真实会话状态已接入 Release composition；未验证帧仍不得进入可见网络内容。

- 实现 `ReceiveOnlyAPRSIdentity`、身份规范化/校验与持久化优先级；默认 App SSID 可编辑且范围限制为 `0...15`。
- 使用 Network.framework Actor 封装 TCP、CRLF 行流、取消、路径恢复和有上限退避；服务器与等待策略可注入。
- 连接地区轮询域名的 `14580` 过滤端口，发送一次 `pass -1` 登录及 `filter u/APFMO4` 控制行；登录完成后从业务接口移除发送能力，禁止发送 APRS 帧。
- 单行上限 512 字节；过长、非 TNC2、非法字节序列、服务器拒绝和登录失败使用类型化错误。

### 3. APRS 与 FMO V4 纯解析

**状态（2026-08-06）：Parser foundation implemented。** 已实现严格 TNC2 与所有规划 `APFMO4` 消息家族的未验证模型，覆盖 token 顺序、字段上限、数值、坐标与 Base64url 长度；尚未开始 CERT CBOR 或任何可信判定。

- 先解析 TNC2 包头、来源呼号/SSID、TOCALL、路径、POSITION/STATUS 与原始 APRS 坐标字符串。
- 再按消息类型解析严格有界的 FMO V4 token；拒绝未知必填字段、数值越界、非法 base64url、错误 token 顺序和超长文本。
- POSITION 与 EVENT STATUS 分开建模；此层不访问网络、时间、存储或 SwiftUI。

### 4. 信任验证

**状态（2026-08-06）：Implemented。** 已实现严格 10 元素 CERT、官方 Root/Intermediate、有效期/UID/国家范围、Root/Intermediate CRL、用户证书与消息 Ed25519、`timeSalt ±1`、去重及 JOINT/EVENT 哈希配对。CRL 支持四小时刷新、网络失败使用已有签名缓存、防低版本回滚，并把未发布、当前、过期、不可用与非法内容分开处理。

- 解析 10 元素 CERT CBOR，重建 TBS，计算 `certFingerprint` / `certBlobHash`，验证 Intermediate 与 Root 信任关系。
- 按当前时间检查 `iat/exp`，验证用户 Ed25519 SIG 与 `timeSalt ±1`，再应用 Root/Intermediate CRL。
- JOINT 缓存只保存有上限的 SH、身份与截止时间；EVENT 必须匹配来源、UID、哈希和期限后才能进入业务层。
- CRL 不可用、未知 issuer、过期、吊销、呼号不匹配、签名失败、重放与配对超时均使用不同验证结果；不得以“收藏”或缓存历史提升可信度。

### 5. 聚合、缓存与收藏

**状态（2026-08-06）：Implemented。** 已建立有上限的台站、服务器、事件、去重集合与 JOINT 缓存；事件采用最近 24 小时且最多 200 条的双重上限。呼号和公共服务器收藏使用两个 SwiftData 模型，与短期 APRS 快照独立。

- 建立可信事件 reducer，以验证时间、消息时间窗口和稳定身份去重；乱序旧帧不得覆盖更新状态。
- `VOCAL` 只生成 `RecentVoiceActivity`，不生成当前说话人；展示 TTL 与签名窗口使用不同可注入策略。
- 台站与服务器短期缓存只保存类型化业务字段和新鲜度，不保存原始 APRS/CERT 帧。
- `FavoriteCallsign` 与 `FavoriteServer` 使用 SwiftData 分离持久化；取消收藏不删除事件、目录或信任材料。

### 6. 原生 UI

**状态（2026-08-06）：Implemented，等待体验验收。** 已完成无身份引导、单层身份 Sheet、紧凑会话条、零数据也可见的地图、最新事件、类型/收藏筛选、台站/服务器/收藏目录、直接搜索、普通详情和星标共享状态；证书链、CRL 与可信等级仅作为内部准入，不进入用户界面。0.6 消息、发送凭据和远控入口未进入原生 0.4。

- FMO 网络首页呈现只读身份/连接状态、地图摘要、过滤器与最新可信事件；点击身份条以底部 Sheet 原地编辑呼号和 App SSID，不增加导航层级。
- 导航栏提供全网与 `50...5000 km` 的本地范围 Menu，默认 `500 km`；首次进入已配置页面时自动取得一次手机位置，失败回退全网，此后有限范围按需定位并统一裁剪地图、目录和事件。地图左下提供默认开启的追踪开关，右下提供一次性本机定位按钮。这些控件不继承或修改盒子距离过滤器，也不改变 APRS 数据订阅。
- 目录支持台站/服务器/收藏分段、搜索、数据年龄和验证状态；星标行与详情共享同一收藏状态。
- 事件流支持全部、CQ、OMCQ、VOCAL、ONLINE、BEACON、STATION 与收藏过滤；JOINT/EVENT 以验证后的业务事件呈现；首页显示最新 3 条并可见 `24h · 200` 保留边界。
- 证书链、有效期、CRL、签名、timeSalt 与 JOINT/EVENT 关系保留在内部类型化验证与测试中，不提供普通用户入口，也不暴露原始证书、帧或精确诊断秘密。
- 消息、发送凭据、远控和通知页面不进入 0.4 原生实现；HTML 中保留它们只是最终产品导航参考。

### 7. 验证与真机验收

- 单元测试：身份优先级、登录/过滤行、绝不发送数据帧、分帧/粘包、行长与取消。
- 协议测试：每种消息的有效/畸形/边界向量、确定性 CBOR、证书链、CRL、签名、timeSalt 与 JOINT 配对。
- 模型测试：去重、乱序、TTL、过期、断线恢复、身份切换与收藏独立性。
- UI 测试：无身份引导、身份 Sheet 保存/取消、只读连接状态、地图、目录、搜索、事件和普通台站详情已覆盖，并断言技术验证与 CRL 状态不出现在用户界面；第二层凭据 Sheet 属于 0.6，不进入本里程碑。
- 网络集成：连接 APRS-IS 过滤端口，证明只收到/处理 `APFMO4`，且测试 transport 证明没有 APRS 数据帧从 App 发出。

## 明确不包含

- APRS PASSCODE、发送、ACK、位置上报、公网远控或局域网管理写操作。
- 后台常驻 APRS-IS、APNs、本地事件到达保证、实时活动或 Dynamic Island。
- 未公开 MQTT 语音、设备私钥、设备身份模拟、网页 DOM 注入或运行时抓包。
- QSO 导入、自建服务器管理和任何以未验证 APRS 数据驱动的危险操作。

## 开发前门槛

- [x] 用户确认更新后的 FMO 网络/身份 Sheet 原型。
- [x] 官方根/中间证书、CRL schema/TBS 与更新策略完成开发 checkpoint；独立证书许可证 URL 留作发布前确认。
- [x] 选定严格最小确定性 CBOR，并用官方 CA 签名和人工完整链路证明兼容；官方完整 APRS 报文字节向量留作发布前交叉验证。
- [x] 建立 `feat/fmo-aprs-readonly` 分支。

阶段 2–6 已进入 Release composition；下一步是阶段 7 的真实 APRS-IS 只读连接、界面/收藏真机验收和全套回归。未通过 `FMOV4Verifier` 的输入仍不得进入可见网络内容。
