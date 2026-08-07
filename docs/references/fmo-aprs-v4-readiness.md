---
last-reviewed: 2026-08-06
status: implementation-unblocked
---

# FMO V4 APRS 协议开发门槛

## 结论

截至 2026-08-06，官方 FMO V4 文档与官方 SAS 源码已经足够实现并联调生产形态的信任验证；原“CA/CRL 签名 TBS 未公开”的开发阻塞已解除。

- **可冻结：** `APFMO4` 包头、512 字符上限、POSITION/STATUS、CQ/OMCQ/VOCAL/ONLINE/BEACON/STATION/JOINT+EVENT、10 元素用户 CERT、各消息 TBS 数组、Ed25519、SHA-256、Base64url 与 `timeSalt ±1`。
- **已解锁：** Root/Intermediate CA、用户证书、Root/Intermediate CRL 的固定顺序 CBOR TBS、Ed25519 验签、指纹规则和 `{}` 未发布语义。
- **发布前待确认：** 证书 JSON 声明的两个独立许可证 URL 仍为 404；官方 APRS 文档仍没有一组未省略字节的完整 CERT/SIG 正反向量。
- **工程约束：** 只有证书链与报文签名通过的数据可进入业务层；已签名 CRL 过期/不可用必须显示真实状态，吊销仍直接拒绝，收藏不得提升可信度。

## 官方依据

- [FMO 4.0 APRS 报文格式 v1.0](https://bg5esn.com/docs/fmo-aprs-formate/)：第三方客户端解析与验证的主规范。
- [FMO 4.0 技术模型](https://bg5esn.com/docs/fmo-model/)：APRS-IS 是发现层，PKI 是信任层，语音连接是独立通联层。
- [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949.html)：CBOR 与确定性编码基线。
- [FMO Server Authorizer Service](https://github.com/BG5ESN/fmo-server-authrozier-service)：官方 SAS 源码；本次核对提交 `a95b15e0cc931b366025bac3e2cdddab69207745`，其中 `RootCaCert`、`IntermediateCaCert`、`UserCert`、`RootCrl`、`IntermediateCrl` 与协议文档公开了完整 TBS。

## 2026-08-06 资源核对

| 资源 | 观察结果 | 判定 |
|---|---|---|
| 官方根证书 | V4 文档内给出完整 JSON、Ed25519 公钥、有效期、CRL 与许可证 URL | 可作为格式证据；分发授权仍未关闭 |
| 官方中间证书 | V4 文档内给出完整 JSON、Ed25519 公钥、UID/国家范围、CRL 与许可证 URL | 官方 SAS 源码已明确 CA 证书签名 TBS，可用于开发验签；分发授权仍待发布前关闭 |
| `root_crl.json` | HTTP 200，正文为 `{}`；官方 `CrlManager` 将空对象记录为 `Root CRL not published yet` | 作为“暂无已知吊销”处理，不伪造签名 CRL；若已有签名缓存则不得被 `{}` 覆盖 |
| `intermediate_crl.json` | CRL #4、2 条吊销，`nextUpdate` 为 2026-06-29 | 可按官方 TBS 验签并执行吊销；当前显示为过期，不标记完全可信 |
| 根许可证 | 官方证书声明的 `license.md` 返回 HTTP 404 | 不阻塞当前开发；发布 App 前需确认公开信任锚分发授权 |
| 中间许可证 | 官方证书声明的 `intermediate_license.md` 返回 HTTP 404 | 不阻塞当前开发；发布 App 前需确认公开信任锚分发授权 |
| 完整报文示例 | CERT、SIG 和哈希均以 `...` 省略 | 不能作为字节级兼容或验签向量 |

官方验证章节把 CRL 查询标为“可选”，但本项目仍执行 CRL。`{}` 表示官方尚未发布列表；签名 CRL 过期或网络不可用时分别保留内部 `stale` 与 `unavailable` 状态，当前不向普通用户展示技术警告。非法 CRL 直接拒绝，任何已匹配的吊销条目都不会因列表过期而放行。

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

该方案已通过 RFC 8949 人工边界、官方 Root 自签名、官方 Intermediate 签名和人工生成的 Root → Intermediate → User → APRS 消息完整链路测试，作为 0.4 实现使用且不增加第三方依赖。完整官方 APRS 报文字节向量仍用于发布前的第二实现交叉验证，而不是继续阻塞开发。

## 解锁条件

1. **开发已满足：** 官方源码明确 CA、用户证书和两类 CRL 的签名输入、规范化与验证步骤。
2. **开发已满足：** Swift 实现可验证官方 Root/Intermediate，并区分未发布、过期、不可用、非法与吊销 CRL。
3. **发布前：** 官方恢复证书声明的许可证 URL，或以其他明确方式确认 App 打包公开信任锚的分发授权。
4. **发布前：** 官方提供至少一组完整 CERT CBOR、TBS CBOR、指纹、blob hash、消息 SIG 与期望结果，用于与 Swift 实现做第二实现交叉验证。
5. **运维跟踪：** Intermediate CRL 恢复当前有效版本；在此之前内部保留 `stale` 状态，用户界面不展示技术信任结论。
