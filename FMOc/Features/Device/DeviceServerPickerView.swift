import SwiftUI

struct DeviceServerPickerView: View {
    @Bindable var model: DeviceHomeModel
    @Environment(\.dismiss) private var dismiss
    var onDismiss: (() -> Void)?
    @State private var searchText = ""
    @State private var selectionTask: Task<Void, Never>?

    init(model: DeviceHomeModel, onDismiss: (() -> Void)? = nil) {
        self.model = model
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            List {
                Section("收藏服务器") {
                    if !filteredPinned.isEmpty {
                        ForEach(filteredPinned) { server in
                            serverRow(server, isPinned: true)
                        }
                    } else if model.isLoadingServerCatalog {
                        loadingRow("正在读取收藏服务器…")
                            .accessibilityIdentifier("favorite-servers-loading")
                    } else if searchText.isEmpty {
                        Label("暂无收藏服务器", systemImage: "star.slash")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = model.serverSelectionError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
                        Button("重新加载") {
                            reload()
                        }
                    }
                }

                Section("所有服务器") {
                    if !filteredAll.isEmpty {
                        ForEach(filteredAll) { server in
                            serverRow(server, isPinned: pinnedUIDs.contains(server.uid))
                        }
                    } else if model.isLoadingServerCatalog {
                        loadingRow("正在读取服务器…")
                    }
                }

                if model.isLoadingServerCatalog, !model.serverCatalog.all.isEmpty {
                    Section {
                        loadingRow("正在加载更多服务器…")
                    }
                }
            }
            .overlay {
                if !model.isLoadingServerCatalog,
                          model.serverCatalog.all.isEmpty,
                          model.serverSelectionError == nil {
                    ContentUnavailableView(
                        "暂无服务器",
                        systemImage: "server.rack",
                        description: Text("设备没有返回可切换的服务器。")
                    )
                } else if !searchText.isEmpty, filteredPinned.isEmpty, filteredAll.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("切换服务器")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索服务器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { closePicker() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新", systemImage: "arrow.clockwise") { reload() }
                        .disabled(model.isLoadingServerCatalog || model.switchingServerUID != nil)
                }
            }
        }
        .task {
            await model.loadServerCatalog()
        }
        .onDisappear { selectionTask?.cancel() }
        .accessibilityIdentifier("device-server-picker")
    }

    private func serverRow(_ server: FmoDeviceServer, isPinned: Bool) -> some View {
        Button {
            guard model.switchingServerUID == nil else { return }
            if model.currentServer?.uid == server.uid {
                closePicker()
                return
            }
            selectionTask?.cancel()
            selectionTask = Task {
                if await model.switchServer(to: server) {
                    closePicker()
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isPinned ? "star.fill" : "server.rack")
                    .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                    .frame(width: 30)
                Text(server.name)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if model.switchingServerUID == server.uid {
                    ProgressView()
                } else if model.currentServer?.uid == server.uid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .fullWidthRowHitArea()
        }
        .buttonStyle(.plain)
        .disabled(model.switchingServerUID != nil && model.switchingServerUID != server.uid)
        .accessibilityValue(model.currentServer?.uid == server.uid ? "当前服务器" : "可切换")
        .accessibilityIdentifier("device-server-\(server.uid)")
    }

    private func loadingRow(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .foregroundStyle(.secondary)
        }
    }

    private var pinnedUIDs: Set<Int64> {
        Set(model.serverCatalog.pinned.map(\.uid))
    }

    private var filteredPinned: [FmoDeviceServer] {
        filtered(model.serverCatalog.pinned)
    }

    private var filteredAll: [FmoDeviceServer] {
        filtered(model.serverCatalog.all)
    }

    private func filtered(_ servers: [FmoDeviceServer]) -> [FmoDeviceServer] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return servers }
        return servers.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func reload() {
        selectionTask?.cancel()
        selectionTask = Task { await model.loadServerCatalog() }
    }

    private func closePicker() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}
