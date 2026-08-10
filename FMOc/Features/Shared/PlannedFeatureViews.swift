import SwiftUI

struct SettingsHomeView: View {
    var body: some View {
        List {
            Section("应用") {
                Label("通知与系统集成", systemImage: "bell")
                Label("外观与显示", systemImage: "circle.lefthalf.filled")
            }
            Section("隐私与安全") {
                Label("权限与数据使用", systemImage: "hand.raised")
                Label("诊断数据", systemImage: "stethoscope")
            }
            Section("关于") {
                LabeledContent("版本", value: "0.1.0")
                LabeledContent("技术基线", value: "iOS 26 · Swift 6")
            }
        }
        .navigationTitle("设置")
    }
}
