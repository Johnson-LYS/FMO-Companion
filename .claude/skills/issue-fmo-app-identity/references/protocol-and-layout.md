# FMO V4 身份签发参考

## 协议来源

- 官方 FMO Server Authorizer Service：<https://github.com/BG5ESN/fmo-server-authrozier-service>
- FMO CA Tool 与协议说明：<https://github.com/bi9bbl/fmo-ca-tool>

FMO 证书不是 X.509。JSON 只用于交换；签名输入是固定字段顺序的确定性 CBOR 数组，签名算法为 Ed25519，二进制字段使用无填充 Base64URL。

User Certificate 的 TBS 为：

```text
["FMO", 4, "userCert", issuerSn, callsign, uid, publicKeyBytes, iat, exp]
```

证书指纹为 `Base64URL(SHA-256(TBS-CBOR))`，不包括 JSON 排版和签名字段。

身份包结构：

```json
{
  "rootCert": { "type": "rootCA" },
  "intermediateCert": { "type": "intermediateCA" },
  "userCert": {
    "type": "userCert",
    "certFingerprint": "..."
  }
}
```

`certFingerprint` 是 App 使用的便利字段，不参与 User Certificate 签名。

## 当前本机布局

```text
~/Library/Application Support/FMOClientProbe/
├── pki-*/
│   ├── root.cert.json
│   ├── intermediate.cert.json
│   └── intermediate.key.json     # 0600，绝不入库
└── uid-registry.sqlite3          # 0600
```

Root 私钥不参与日常用户签发。脚本只需要 Root 公共证书、Intermediate 公共证书及 Intermediate 私钥。

当前 BI8SYN 自建 Root 指纹：

```text
DXAB2NsFmA93iwk27m6jPDC-mMeOZ9rnmoD6uAK22uA
```

## 信任含义

完整链为 `自建 Root -> App Intermediate -> User Certificate`。只有已经把自建 Root 加入 trust store 的 SAS 才会接受这条链。服务器集群传播语音不等于传播或继承 CA 信任；每个鉴权入口仍按自己的 trust store 判定连接身份。
