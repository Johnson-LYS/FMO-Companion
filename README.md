# FMO Companion

FMO Companion 是面向 FMO（NFM Over Internet）盒子的原生 iOS 伴侣应用。项目只使用公开协议和用户授权的接口。0.1–0.6 已完成局域网设备、可靠定位、设备仪表盘、可信 FMO APRS 网络、前台消息与远控；下一阶段为 0.8 QSO。

## 技术基线

- iOS 26+
- SwiftUI
- Swift Concurrency
- Swift Testing / XCUITest
- Apple Network、Core Location、MapKit、CryptoKit、Keychain、WebKit

## 开始工作

1. 使用 Xcode 打开 `FMOc.xcodeproj`。
2. 阅读 `AGENTS.md` 和 `docs/project-brief.md`。
3. 当前路线图见 `docs/plans/0003-product-roadmap.md`；开始新阶段前先阅读 `docs/project-brief.md`。
4. 选择本机可用的 iPhone Simulator 或真实 iPhone 运行测试。

## 文档

文档采用 [Loom](https://github.com/The-Last-Humans/loom) 的文档驱动结构：

- `docs/project-brief.md`：每次会话的快速入口。
- `docs/spec/`：产品与技术规格。
- `docs/architecture/`：架构和模块边界。
- `docs/adr/`：重要架构决策。
- `docs/plans/`：可执行计划和里程碑。
- `docs/references/`：官方协议与能力边界。

Loom 只用于初始化和维护方法，不是 App 的运行时依赖。
