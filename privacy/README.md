# 隐私政策部署

`privacy/index.html` 是无 JavaScript、Cookie、外部字体、远程图片、CDN 或构建依赖的静态页面。

## 部署

当前正式地址为：

```text
https://fmo-companion.bi8syo.com/privacy/
```

`deploy/` 提供项目当前使用的 Caddy Docker Compose 配置。Caddy 会自动申请、续期并热加载 HTTPS 证书；证书状态保存在 Docker volume 中。

首次部署：

```bash
docker compose -f privacy/deploy/compose.yaml up -d
```

后续只需替换 `privacy/index.html`；该文件以只读 bind mount 直接提供，无需重建镜像或重启容器。

服务器只需把该目录的 `index.html` 作为默认页面返回。部署后确认：

1. 无登录状态下可访问，并返回 `200`。
2. 手机与桌面浏览器均能完整缩放和阅读。
3. HTTP 自动跳转到 HTTPS。
4. 地址长期稳定，且与 App Store Connect 中填写的隐私政策 URL 相同。

## 配置 App

部署完成后，将 `FMOc/Info.plist` 的 `FMOPrivacyPolicyURL` 设置为最终 HTTPS 地址。未配置有效 HTTPS 地址的开发构建会显示内容一致的 App 内政策页，不会打开失效链接。
