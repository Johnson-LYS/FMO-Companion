# FMO Companion HTML 原型

这是正式 SwiftUI 开发前的交互与视觉验证稿。原型不访问真实 FMO、局域网、位置或凭据，所有设备、呼号、坐标、消息和服务器状态都是虚构示例。

## 打开方式

在仓库根目录执行：

```bash
python3 -m http.server 4173 -d prototype
```

然后访问 `http://127.0.0.1:4173/`。

## 可评审内容

- 页面只展示接近最终 App 的用户界面，不包含规格跳转、里程碑或评审工具。
- 首页可演示自动发现、手动地址、连接、坐标同步、诊断和设备远控。
- 底部标签可进入 0.2、0.4、0.6、0.8 和 1.0 的代表性功能流程。
- 用户层底部只保留首页、FMO 网络、QSO、设置四个标签。
- 危险远控会显示二次确认，但不会发送任何命令。
- FMO 网络页包含台站目录、事件流、消息和按需展开的身份验证详情。
- QSO 页包含导入验证、查询详情和 ADIF 导出。
- 设置页包含管理员功能、通知、小组件、快捷指令、隐私无障碍与产品边界。

设计规则见 `docs/design/ui-design-system.md`，规格映射见 `docs/design/prototype-coverage-matrix.md`，后续 AI 开发必须读取 `docs/design/prototype-implementation-guide.md`。
