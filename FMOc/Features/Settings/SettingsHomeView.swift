import SwiftUI
import UIKit

struct SettingsHomeView: View {
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue
    @Environment(\.openURL) private var openURL

    private let metadata = AppMetadata()

    var body: some View {
        List {
            Section("外观") {
                Picker("外观模式", selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("appearance-picker")
            }

            Section("隐私") {
                if let privacyPolicyURL = AppLinks.privacyPolicyURL {
                    Link(destination: privacyPolicyURL) {
                        settingsRow("隐私政策", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("privacy-policy-link")
                } else {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        settingsRow("隐私政策", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("privacy-policy-link")
                }

                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                } label: {
                    settingsRow("系统权限", systemImage: "gear")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("system-permissions-link")
            }

            Section("关于") {
                NavigationLink {
                    AboutView(metadata: metadata)
                } label: {
                    settingsRow("关于 FMO 助手", systemImage: "info.circle")
                }
                .accessibilityIdentifier("about-entry")

                LabeledContent("版本", value: metadata.versionDescription)
                    .accessibilityIdentifier("app-version")
            }
        }
        .navigationTitle("设置")
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    private func settingsRow(_ title: LocalizedStringResource, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
    }
}

private struct AboutView: View {
    let metadata: AppMetadata

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(metadata.name)
                        .font(.title2.bold())
                    Text("连接 FMO、查看网络动态、收发 APRS 消息并管理通联记录。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("开发者") {
                LabeledContent("呼号", value: AppLinks.developerCallsign)
                    .accessibilityIdentifier("developer-callsign")
                Link(destination: AppLinks.contactURL) {
                    LabeledContent("联系邮箱", value: AppLinks.contactEmail)
                }
                .accessibilityIdentifier("developer-email")
            }

            Section("版本") {
                LabeledContent("版本与构建", value: metadata.versionDescription)
                    .accessibilityIdentifier("about-version")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        List {
            policySection(
                "我们如何使用数据",
                "FMO 助手仅为连接你选择的 FMO、同步位置、接入 APRS 网络以及在本机保存消息与 QSO 记录而处理必要数据。我们不提供广告，不进行跨 App 跟踪，也不出售个人数据。"
            )
            policySection(
                "公开网络",
                "呼号、APRS 消息和远控命令会经过 APRS-IS 公网传输，不应被视为私密或端到端加密通信。远控凭据原文只保存在本机，不会随命令发送。"
            )
            policySection(
                "位置与本地数据",
                "位置仅用于地图范围和向你选择的 FMO 同步。设备信息、收藏、消息历史和 QSO 缓存保存在本机；ADIF 仅在你主动导出后交给系统分享。"
            )
            policySection(
                "设备接收音频",
                "横屏仪表盘位于前台时，App 会从你选择的 FMO 接收音频并在本机生成波形；声音默认关闭。音频不录制、不保存、不上传，也不用于识别讲话者。"
            )
            Section("联系我们") {
                LabeledContent("开发者", value: AppLinks.developerCallsign)
                Link(AppLinks.contactEmail, destination: AppLinks.contactURL)
            }
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(_ title: LocalizedStringResource, _ text: LocalizedStringResource) -> some View {
        Section(title) {
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
