import XCTest

final class FMOcUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeShowsPrimaryConnectionPathAndTabs() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "empty"
        app.launch()

        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["device-discovery-toggle"].exists)
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

    @MainActor
    func testConnectedDashboardUsesGeoDerivedMaidenheadWithoutDeferredFixtures() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "dashboard-connected"
        app.launch()

        let deviceRow = app.buttons["device-row-fmo.local:80"]
        XCTAssertTrue(deviceRow.waitForExistence(timeout: 5))
        deviceRow.tap()

        let callsign = app.descendants(matching: .any)["dashboard-callsign"]
        XCTAssertTrue(callsign.waitForExistence(timeout: 10))
        XCTAssertTrue(callsign.label.contains("BG0TST"))
        let server = app.descendants(matching: .any)["dashboard-server-name"]
        XCTAssertTrue(server.waitForExistence(timeout: 2))
        XCTAssertTrue(server.label.contains("测试服务器"))
        let maidenhead = app.descendants(matching: .any)["dashboard-maidenhead-value"]
        XCTAssertTrue(maidenhead.waitForExistence(timeout: 2))
        XCTAssertEqual(maidenhead.value as? String, "PM01rf")
        XCTAssertFalse(app.staticTexts["438.500"].exists)
        XCTAssertFalse(app.buttons["断开连接"].exists)
        XCTAssertFalse(app.staticTexts["示例华东服务器"].exists)
        XCTAssertFalse(app.staticTexts["BI8SYN"].exists)
        XCTAssertFalse(app.staticTexts["GEO 会话"].exists)
        XCTAssertFalse(app.staticTexts["公开局域网接口"].exists)
        XCTAssertFalse(app.staticTexts["由 FMO 坐标换算"].exists)
    }

    @MainActor
    func testLaunchAutomaticallyConnectsFirstDiscoveredDevice() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "automatic-connection"
        app.launch()

        let maidenhead = app.descendants(matching: .any)["dashboard-maidenhead-value"]
        XCTAssertTrue(maidenhead.waitForExistence(timeout: 10))
        XCTAssertEqual(maidenhead.value as? String, "PM01rf")

        let deviceRow = app.buttons["device-row-fmo.local:80"]
        XCTAssertTrue(deviceRow.exists)
        XCTAssertTrue(deviceRow.isSelected)
        XCTAssertFalse(app.buttons["断开连接"].exists)
    }

    @MainActor
    func testLocationAutomationExplainsAutomaticModeBeforeEnabling() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "saved-device"
        app.launch()

        let entry = app.buttons["location-automation-entry"]
        if !entry.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        XCTAssertTrue(app.navigationBars["位置自动化"].waitForExistence(timeout: 2))
        app.buttons["location-mode-lowPower"].tap()

        let confirmation = app.alerts["启用低功耗？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(
            confirmation.staticTexts[
                "首次有效位置会立即同步，之后达到 15 分钟或移动 1 公里时同步。需要“始终”定位授权。"
            ].exists
        )
    }

    @MainActor
    func testOfficialPagesRequireDeviceAndPresentSystemBrowser() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "empty"
        app.launch()

        let management = app.buttons["official-management-entry"]
        if !management.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(management.waitForExistence(timeout: 5))
        management.tap()
        XCTAssertTrue(app.alerts["无法打开 FMO 页面"].waitForExistence(timeout: 2))
        app.alerts["无法打开 FMO 页面"].buttons["知道了"].tap()

        app.terminate()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "saved-device"
        app.launch()

        let qso = app.buttons["official-qso-entry"]
        if !qso.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(qso.waitForExistence(timeout: 5))
        qso.tap()
        XCTAssertTrue(app.otherElements["official-safari-view"].waitForExistence(timeout: 5))
    }
}
