---
last-reviewed: 2026-08-06
status: blocked
---

# FMO V4 APRS 协议开发门槛

## 结论

截至 2026-08-06，官方 FMO V4 文档已经足够冻结 APRS/TNC2 解析、消息类型、CERT 用户证书结构和消息 TBS 字段顺序，但还不足以安全交付生产级信任验证。

- **可冻结：** `APFMO4` 包头、512 字符上限、POSITION/STATUS、CQ/OMCQ/VOCAL/ONLINE/BEACON/STATION/JOINT+EVENT、10 元素用户 CERT、各消息 TBS 数组、Ed25519、SHA-256、Base64url 与 `timeSalt ±1`。
- **继续阻塞：** 根/中间 CRL 的完整有效 schema、CA/CRL 签名 TBS 规则、可分发许可证和至少一组没有省略字节的官方 CERT/SIG 测试向量。
- **工程约束：** 在阻塞项关闭前，不把任何 APRS 数据标记为“可信”，不加入生产验签器，也不通过跳过 CRL、接受过期 CRL 或自造兼容规则来推进里程碑。

## 官方依据

- [FMO 4.0 APRS 报文格式 v1.0](https://bg5esn.com/docs/fmo-aprs-formate/)：第三方客户端解析与验证的主规范。
- [FMO 4.0 技术模型](https://bg5esn.com/docs/fmo-model/)：APRS-IS 是发现层，PKI 是信任层，语音连接是独立通联层。
- [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949.html)：CBOR 与确定性编码基线。

## 2026-08-06 资源核对

| 资源 | 观察结果 | 判定 |
|---|---|---|
| 官方根证书 | V4 文档内给出完整 JSON、Ed25519 公钥、有效期、CRL 与许可证 URL | 可作为格式证据；分发授权仍未关闭 |
| 官方中间证书 | V4 文档内给出完整 JSON、Ed25519 公钥、UID/国家范围、CRL 与许可证 URL | 可作为格式证据；CA 证书签名 TBS 规则未明确 |
| `root_crl.json` | HTTP 200，但正文仅为 `{}`，最后修改于 2026-06-14 | 不能证明 root CRL schema、签名或新鲜度 |
| `intermediate_crl.json` | 有 `issuerSn/crlNumber/thisUpdate/nextUpdate/entries/signature`，但 `nextUpdate` 为 2026-06-29 | schema 可参考；当前已过期，且签名 TBS 规则未明确 |
| 根许可证 | 官方证书声明的 `license.md` 返回 HTTP 404 | 阻塞随 App 分发根信任材料 |
| 中间许可证 | 官方证书声明的 `intermediate_license.md` 返回 HTTP 404 | 阻塞随 App 分发中间信任材料 |
| 完整报文示例 | CERT、SIG 和哈希均以 `...` 省略 | 不能作为字节级兼容或验签向量 |

官方验证章节把 CRL 查询标为“可选”，但本项目的可信 UI 要求完整验证。CRL 缺失、过期或不可验证时只能显示独立的“不确定/吊销状态过期”结果，不能降级为可信。

## CBOR 技术候选

FMO 用户 CERT 与消息 TBS 只使用固定长度数组及以下 CBOR 类型：

- major type 0：无符号整数；
- major type 2：字节串；
- major type 3：UTF-8 文本；
- major type 4：固定长度数组。

因此优先候选是项目内极小、严格、无状态的 RFC 8949 编解码器，而不是通用 Codable/CBOR 依赖：

- 编码只产生最短整数/长度形式和固定长度数组；
- 解码拒绝不定长、map、tag、float、负数、尾随字节、过深嵌套和超出协议上限的长度；
- CERT 必须恰好 10 个元素并严格检查每一项类型和尺寸；
- TBS 使用类型化模型按官方固定顺序构造，不接受任意 CBOR 树；
- SHA-256 与 Ed25519 使用 CryptoKit；时钟通过协议注入。

该候选只有在 RFC 8949 向量、人工边界向量和完整官方 FMO 向量全部通过后才能转为正式架构决定；此前不新增第三方依赖，也不创建 ADR。

## 解锁条件

1. 官方发布可访问的根/中间证书许可证，或明确允许 App 打包/分发信任锚。
2. 官方发布当前有效且可验签的 Root/Intermediate CRL，并明确两类 CRL 的确定性签名 TBS。
3. 官方明确 CA 证书 JSON 的签名输入、规范化和验证步骤。
4. 官方提供至少一组完整 CERT CBOR、TBS CBOR、指纹、blob hash、消息 SIG 与期望结果；最好同时包含吊销和失败向量。
5. 用相同向量证明 Swift 实现与官方实现字节级一致后，再开始生产信任验证。
