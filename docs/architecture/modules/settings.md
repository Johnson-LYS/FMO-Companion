---
last-reviewed: 2026-08-10
---

# 模块：设置

## 目的

设置模块只承载已经交付的全局 App 偏好、隐私入口和产品信息。首版采用最小信息架构，不用不可点击的列表行预告通知、自建服务器、快捷指令、小组件、实时活动或诊断导出。

## 公共接口

```swift
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? { get }
}

struct AppMetadata: Equatable {
    init(bundle: Bundle = .main)

    let name: String
    let version: String
    let build: String
    var versionDescription: String { get }
}
```

`SettingsHomeView` 是设置导航栈的唯一首页。根 `ContentView` 读取与设置页相同的 `AppStorage` 键，把选择投影为全局 `preferredColorScheme`；未知或未来存储值回退为跟随系统。

## 内部结构

- 外观使用稳定字符串枚举持久化，不保存系统当前明暗状态。用户选择立即影响整个根视图，重新启动后恢复。
- `AppMetadata` 从 Bundle 读取显示名、版本和构建号，避免发布时出现硬编码版本漂移。
- 关于页显示产品用途、开发者呼号 `BI8SYN` 和 `mailto:BI8SYN@163.com`，不展示开发技术栈。
- 隐私政策 URL 从 `Info.plist` 的 `FMOPrivacyPolicyURL` 集中读取，只接受带主机的 HTTPS 地址。未配置时，开发构建进入内容一致的 App 内政策页，不打开无效地址。
- 系统权限入口只调用 `UIApplication.openSettingsURLString`，不推断或伪造所有权限的综合状态。
- 公网政策正文位于 `privacy/index.html`，不进入 App Bundle，也不依赖 JavaScript、Cookie、分析、第三方字体、远程图片或 CDN。

## 数据流

```text
appearance Picker
→ AppStorage(app.appearance)
→ ContentView preferredColorScheme

Bundle / Info.plist
→ AppMetadata + optional HTTPS policy URL
→ SettingsHomeView / AboutView / external policy
```

## 依赖与边界

- SwiftUI：设置列表、导航、外观投影与本地偏好。
- Foundation / Bundle：版本、构建号和集中链接配置。
- UIKit：打开 iOS 的 App 设置页面。
- 设置模块不读取设备状态、APRS 身份、QSO 内容、位置或任何秘密。
- 远控 SECRET 仍只在设备远控设置中管理；消息、设备、收藏和 QSO 的删除操作留在对应功能页。
- 正式发布前，`FMOPrivacyPolicyURL` 必须配置为与 App Store Connect 相同的稳定公网 HTTPS 地址。

## 关键文件

- `FMOc/Features/Settings/AppAppearance.swift`
- `FMOc/Features/Settings/AppMetadata.swift`
- `FMOc/Features/Settings/SettingsHomeView.swift`
- `FMOc/ContentView.swift`
- `privacy/index.html`

## 测试

- 单元测试覆盖三种外观映射、未知持久化值回退和动态 Bundle 元数据。
- XCUITest 覆盖设置入口、隐私政策、系统权限、关于、开发者信息与动态版本，并确认首版页面不再出现通知、管理员和诊断占位或技术栈。
- 通用模拟器构建验证 DEBUG/Release 共用的新文件同步和 Info.plist 结构。
