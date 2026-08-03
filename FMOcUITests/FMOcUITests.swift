import XCTest

final class FMOcUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeShowsPrimaryConnectionPathAndTabs() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["发现附近的 FMO"].exists)
        XCTAssertTrue(app.buttons["首页"].exists)
        XCTAssertTrue(app.buttons["FMO 网络"].exists)
        XCTAssertTrue(app.buttons["QSO"].exists)
        XCTAssertTrue(app.buttons["设置"].exists)

        let diagnosticsRow = app.buttons["连接诊断"]
        XCTAssertTrue(diagnosticsRow.exists)
        diagnosticsRow.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["连接诊断"].waitForExistence(timeout: 2))
        app.buttons["完成"].tap()

        app.buttons["手动地址"].tap()
        XCTAssertTrue(app.navigationBars["手动连接"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["主机名或 IPv4"].exists)
        XCTAssertTrue(app.textFields["端口（可选）"].exists)
    }

    @MainActor
    func testLocalNetworkDenialOffersSettingsRecovery() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "local-network-denied"
        app.launch()

        app.buttons["发现附近的 FMO"].tap()

        let alert = app.alerts["本地网络访问已关闭"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(alert.buttons["前往设置"].exists)
        XCTAssertTrue(alert.buttons["暂不"].exists)

        alert.buttons["暂不"].tap()
        XCTAssertFalse(alert.exists)
    }
}
