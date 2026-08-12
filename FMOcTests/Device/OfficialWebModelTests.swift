import Foundation
import Testing
@testable import FMOc

@MainActor
struct OfficialWebModelTests {
    @Test(arguments: [FmoOfficialPage.management, .qso])
    func createsDestinationForSelectedDevice(page: FmoOfficialPage) throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let model = OfficialWebModel()

        model.open(page, endpoint: endpoint)

        #expect(model.destination?.page == page)
        #expect(model.issue == nil)
    }

    @Test
    func missingDeviceProducesActionableIssue() {
        let model = OfficialWebModel()

        model.open(.management, endpoint: nil)

        #expect(model.destination == nil)
        #expect(model.issue?.title == String(localized: "无法打开 FMO 页面"))
        #expect(model.issue?.message == String(localized: "请先在设备页发现、手动添加或选择一台 FMO 设备，然后重试。"))
    }

    @Test
    func invalidGeneratedURLProducesRecoveryGuidance() throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let model = OfficialWebModel(urlBuilder: FailingOfficialWebURLBuilder())

        model.open(.qso, endpoint: endpoint)

        #expect(model.destination == nil)
        #expect(model.issue?.title == String(localized: "FMO 页面地址无效"))
        #expect(model.issue?.message == String(localized: "请删除这台设备并重新发现，或检查手动输入的主机和端口。"))
    }
}

private nonisolated struct FailingOfficialWebURLBuilder: FmoOfficialWebURLBuilding {
    func url(for page: FmoOfficialPage, endpoint: FmoDeviceEndpoint) throws -> URL {
        throw FmoDeviceEndpoint.ValidationError.unsupportedAddress
    }
}
