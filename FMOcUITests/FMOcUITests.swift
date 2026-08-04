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
        if !diagnosticsRow.exists { app.swipeUp() }
        XCTAssertTrue(diagnosticsRow.waitForExistence(timeout: 2))
        diagnosticsRow.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["连接诊断"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["首页当前未连接"].exists)
        XCTAssertTrue(app.staticTexts["以下结果是独立可达性检查，不代表首页已建立连接。"].exists)
        app.buttons["完成"].tap()

        app.swipeDown()
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

    @MainActor
    func testSavedDeviceCanBeRemoved() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "saved-device"
        app.launch()

        let deviceRow = app.buttons["device-row-fmo.local:80"]
        if !deviceRow.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(deviceRow.waitForExistence(timeout: 5))
        deviceRow.swipeLeft()
        app.buttons["删除"].tap()

        let confirmation = app.sheets["删除这台设备？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.buttons["删除设备"].tap()

        XCTAssertTrue(app.staticTexts["尚未发现设备"].waitForExistence(timeout: 2))
    }
}
