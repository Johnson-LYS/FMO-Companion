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
        #expect(model.issue?.title == "无法打开 FMO 页面")
        #expect(model.issue?.message.contains("选择一台 FMO") == true)
    }

    @Test
    func invalidGeneratedURLProducesRecoveryGuidance() throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let model = OfficialWebModel(urlBuilder: FailingOfficialWebURLBuilder())

        model.open(.qso, endpoint: endpoint)

        #expect(model.destination == nil)
        #expect(model.issue?.title == "FMO 页面地址无效")
        #expect(model.issue?.message.contains("重新发现") == true)
    }
}

private nonisolated struct FailingOfficialWebURLBuilder: FmoOfficialWebURLBuilding {
    func url(for page: FmoOfficialPage, endpoint: FmoDeviceEndpoint) throws -> URL {
        throw FmoDeviceEndpoint.ValidationError.unsupportedAddress
    }
}
