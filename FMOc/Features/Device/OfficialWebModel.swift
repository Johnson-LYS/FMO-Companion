import Foundation
import Observation

nonisolated protocol FmoOfficialWebURLBuilding: Sendable {
    func url(for page: FmoOfficialPage, endpoint: FmoDeviceEndpoint) throws -> URL
}

nonisolated struct FmoOfficialWebURLBuilder: FmoOfficialWebURLBuilding {
    func url(for page: FmoOfficialPage, endpoint: FmoDeviceEndpoint) throws -> URL {
        try endpoint.officialWebURL(for: page)
    }
}

@MainActor
@Observable
final class OfficialWebModel {
    struct Destination: Identifiable, Equatable {
        let page: FmoOfficialPage
        let url: URL

        var id: String { page.rawValue }
    }

    struct Issue: Identifiable, Equatable {
        let title: String
        let message: String

        var id: String { title + message }
    }

    private let urlBuilder: any FmoOfficialWebURLBuilding

    var destination: Destination?
    var issue: Issue?

    init(urlBuilder: any FmoOfficialWebURLBuilding = FmoOfficialWebURLBuilder()) {
        self.urlBuilder = urlBuilder
    }

    func open(_ page: FmoOfficialPage, endpoint: FmoDeviceEndpoint?) {
        guard let endpoint else {
            issue = Issue(
                title: String(localized: "无法打开 FMO 页面"),
                message: String(localized: "请先在首页发现、手动添加或选择一台 FMO 设备，然后重试。")
            )
            return
        }

        do {
            destination = Destination(
                page: page,
                url: try urlBuilder.url(for: page, endpoint: endpoint)
            )
        } catch {
            issue = Issue(
                title: String(localized: "FMO 页面地址无效"),
                message: String(localized: "请删除这台设备并重新发现，或检查手动输入的主机和端口。")
            )
        }
    }

    func clearIssue() {
        issue = nil
    }
}
