---
name: issue-fmo-app-identity
description: 为 FMO App 客户端公钥分配不重复 UID，使用本机自建 FMO Intermediate CA 签发、登记并验证 FMO V4 身份包。用户要求签发 App 身份、客户端证书、补发身份包、检查证书链或查询已分配 UID 时使用。
---

# 签发 FMO App 身份

## 目标

把调用方提供的 32 字节 Ed25519 公钥转换成可导入 FMO Companion 的身份包。私钥只从本机受限目录读取，不复制到项目、输出包、日志或命令行参数中。

## 前置边界

- 只为已经完成合规审核的呼号签发。
- 客户端必须自行生成并保管私钥；签发方只接收 Base64URL 公钥。
- Root/Intermediate 私钥不得进入 Git、聊天、日志或身份包。
- 自建 Root 只对已显式信任它的 SAS 有效；不能替代官方 Root，也不会自动获得其他服务器信任。
- 首次在新环境使用前，读取 [协议与本机布局](references/protocol-and-layout.md)。

## 签发流程

1. 确认申请信息至少包含：呼号、公钥、稳定且可审计的设备标签。标签建议使用 `ios-<用途>-<公钥前12位>`。
2. 规范化呼号为大写；不要替用户推测不同呼号或复用旧设备标签。
3. 先列出现有登记：

   ```bash
   python3 .claude/skills/issue-fmo-app-identity/scripts/fmo_identity_issuer.py list
   ```

4. 签发。默认从 Intermediate 授权区间中原子分配下一个 UID，身份包写入 `~/Downloads`：

   ```bash
   python3 .claude/skills/issue-fmo-app-identity/scripts/fmo_identity_issuer.py issue \
     --callsign BI8SYN \
     --public-key '<BASE64URL_PUBLIC_KEY>' \
     --label 'ios-primary-<PUBLIC_KEY_PREFIX>' \
     --expected-root-fingerprint 'DXAB2NsFmA93iwk27m6jPDC-mMeOZ9rnmoD6uAK22uA'
   ```

5. 对生成的包再次做完整链路和有效期验证：

   ```bash
   python3 .claude/skills/issue-fmo-app-identity/scripts/fmo_identity_issuer.py verify \
     --bundle '<ABSOLUTE_PATH_TO_IDENTITY_JSON>'
   ```

6. 只向用户交付 `.identity.json`。输出包仅含公开证书，不含客户端或 CA 私钥；仍按身份资料谨慎传输。

## UID 规则

- 默认自动分配，不手工心算 UID。
- SQLite 使用 `BEGIN IMMEDIATE` 和 `uid` 主键保证并发签发不重复。
- `(callsign, label)` 唯一；同标签再次签发会失败关闭，避免误生成第二个身份。
- 显式 `--uid` 只用于迁移既有登记，且必须在 Intermediate 的授权区间内。
- 换设备密钥时使用新标签；撤销/轮换是独立运维动作，不能用覆盖旧登记代替。
- 旧身份包用 `register --bundle ... --label ... --expected-root-fingerprint ...` 回填公钥和指纹；该命令只接受完整验签通过且与既有 UID/标签一致的记录。

## 路径与覆盖

脚本按以下顺序解析本机材料：

1. 命令行 `--pki-dir` / `--registry`；
2. `FMO_PKI_DIR` / `FMO_UID_REGISTRY` 环境变量；
3. `FMO_IDENTITY_ISSUER_HOME`（默认 `~/Library/Application Support/FMOClientProbe`）下唯一的 `pki-*` 目录和 `uid-registry.sqlite3`。

输出默认拒绝覆盖。若发现多个 PKI 目录，必须显式指定，不能猜测。
当前 BI8SYN 自建 Root 指纹为 `DXAB2NsFmA93iwk27m6jPDC-mMeOZ9rnmoD6uAK22uA`；日常签发必须通过参数或 `FMO_EXPECTED_ROOT_FINGERPRINT` 固定该信任锚。CA 正式轮换后同步更新本 Skill，不可临时跳过核对。

## 故障处理

- `CryptoKit` 不可用：在安装 Xcode Command Line Tools 的 macOS 主机签发；不要临时上传 CA 私钥到在线服务。
- Root/Intermediate 验签失败或密钥不匹配：立即停止，不生成证书。
- UID、标签或公钥冲突：读取登记并核实申请，不删除记录、不强制覆盖。
- Intermediate 即将过期或申请有效期超界：先按 CA 轮换流程处理，不截短有效期来隐藏问题。
- SAS 拒绝该身份：用 `deploy-fmo-server` 检查 SAS trust store 是否已安装该 Root；不要重复签发碰运气。
