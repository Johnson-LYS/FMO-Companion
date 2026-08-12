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

        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open-device-picker"].exists)
        XCTAssertFalse(app.buttons["device-discovery-toggle"].exists)
        XCTAssertTrue(app.buttons["设备"].exists)
        XCTAssertTrue(app.buttons["FMO 网络"].exists)
        XCTAssertTrue(app.buttons["QSO"].exists)
        XCTAssertTrue(app.buttons["设置"].exists)

        let diagnosticsRow = app.buttons["连接诊断"]
        if !diagnosticsRow.exists { app.swipeUp() }
        XCTAssertTrue(diagnosticsRow.waitForExistence(timeout: 2))
        diagnosticsRow.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["连接诊断"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["设备当前未连接"].exists)
        XCTAssertTrue(app.staticTexts["以下结果是独立可达性检查，不代表设备页已建立连接。"].exists)
        app.buttons["完成"].tap()

        app.swipeDown()
        app.buttons["open-device-picker"].tap()
        XCTAssertTrue(app.navigationBars["选择设备"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["device-discovery-toggle"].exists)
        app.buttons["manual-address-entry"].tap()
        XCTAssertTrue(app.navigationBars["手动连接"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["主机名或 IPv4"].exists)
        XCTAssertTrue(app.textFields["端口（可选）"].exists)
    }

    @MainActor
    func testFMONetworkIdentityCanBeConfiguredAndStartsReceiving() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "empty"
        app.launch()

        app.buttons["FMO 网络"].tap()
        XCTAssertTrue(app.navigationBars["FMO 网络"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["APRS 消息"].exists)

        let setup = app.buttons["aprs-identity-setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 2))
        setup.tap()

        XCTAssertTrue(app.navigationBars["网络身份"].waitForExistence(timeout: 2))
        let callsign = app.textFields["aprs-callsign-field"]
        XCTAssertTrue(callsign.exists)
        callsign.tap()
        callsign.typeText("BG0TST")
        app.buttons["aprs-identity-save"].tap()

        let session = app.buttons["aprs-session-bar"]
        XCTAssertTrue(session.waitForExistence(timeout: 2))
        let receiving = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "正在接收"),
            object: session
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [receiving], timeout: 5),
            .completed,
            "Unexpected session value: \(String(describing: session.value))"
        )
        XCTAssertTrue((session.value as? String)?.contains("BG0TST-10") == true)
    }

    @MainActor
    func testFMONetworkShowsMapSearchableDirectoryAndEvents() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "aprs-network-content"
        app.launch()

        app.buttons["FMO 网络"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["aprs-network-map"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["aprs-map-auto-tracking"].exists
        )
        XCTAssertTrue(app.buttons["aprs-map-my-location"].exists)
        let distanceScopeMenu = app.buttons["aprs-distance-scope-menu"]
        XCTAssertTrue(distanceScopeMenu.exists)
        XCTAssertEqual(distanceScopeMenu.value as? String, "当前位置 500 公里内")
        XCTAssertTrue(app.staticTexts["1 个台站"].exists)
        XCTAssertTrue(app.staticTexts["保留最近 24 小时，最多 200 条"].exists)
        XCTAssertFalse(app.staticTexts["吊销信息待更新"].exists)
        XCTAssertFalse(app.staticTexts["身份验证"].exists)
        XCTAssertTrue(app.staticTexts["BG0AAA · CQ"].exists)

        app.swipeUp()
        XCTAssertTrue(distanceScopeMenu.exists)

        let directory = app.buttons["aprs-station-directory-entry"]
        if !directory.exists { app.swipeUp() }
        XCTAssertTrue(directory.waitForExistence(timeout: 2))
        directory.tap()
        XCTAssertTrue(app.navigationBars["台站与服务器"].waitForExistence(timeout: 2))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("BG0AAA")
        let station = app.staticTexts["BG0AAA-10"]
        XCTAssertTrue(station.exists)
        station.tap()
        XCTAssertTrue(app.navigationBars["台站详情"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["身份验证"].exists)
        XCTAssertFalse(app.staticTexts["吊销信息待更新"].exists)
    }

    @MainActor
    func testLocalNetworkDenialOffersSettingsRecovery() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "local-network-denied"
        app.launch()

        let alert = app.alerts["本地网络访问已关闭"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.buttons["前往设置"].exists)
        XCTAssertTrue(alert.buttons["暂不"].exists)

        alert.buttons["暂不"].tap()
        XCTAssertFalse(alert.exists)
    }

    @MainActor
    func testSavedDeviceCanBeRemoved() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "saved-device"
        app.launch()

        let selector = app.buttons["dashboard-device-selector"]
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        selector.tap()
        let deviceRow = app.buttons["device-row-fmo.local:80"]
        XCTAssertTrue(deviceRow.waitForExistence(timeout: 5))
        deviceRow.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertFalse(app.sheets["删除这台设备？"].exists)
        XCTAssertTrue(deviceRow.waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testMessagesAndRemoteControlFollowApprovedHierarchy() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "aprs-network-content"
        app.launch()

        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 5))
        let remoteControl = app.buttons["remote-control-entry"]
        if !remoteControl.exists { app.swipeUp() }
        XCTAssertTrue(remoteControl.waitForExistence(timeout: 5))
        remoteControl.tap()
        XCTAssertTrue(app.navigationBars["远程控制"].waitForExistence(timeout: 2))
        app.buttons["remote-control-settings"].tap()
        XCTAssertTrue(app.navigationBars["远控设置"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.secureTextFields["12 位凭据"].exists)
        app.buttons["取消"].tap()

        app.buttons["FMO 网络"].tap()
        let messages = app.buttons["aprs-messages-entry"]
        if !messages.exists { app.swipeUp() }
        XCTAssertTrue(messages.waitForExistence(timeout: 5))
        messages.tap()
        XCTAssertTrue(app.navigationBars["APRS 消息"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["aprs-new-message"].exists)
        XCTAssertTrue(app.staticTexts["已连接"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsContainsOnlyWorkingReleaseEntries() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "empty"
        app.launch()

        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["appearance-picker"].exists)
        XCTAssertTrue(app.buttons["privacy-policy-link"].exists)
        XCTAssertTrue(app.buttons["system-permissions-link"].exists)
        XCTAssertTrue(app.buttons["about-entry"].exists)
        XCTAssertFalse(app.staticTexts["通知与系统集成"].exists)
        XCTAssertFalse(app.staticTexts["管理员功能"].exists)
        XCTAssertFalse(app.staticTexts["诊断数据"].exists)

        app.buttons["about-entry"].tap()
        XCTAssertTrue(app.navigationBars["关于"].waitForExistence(timeout: 2))
        let developer = app.descendants(matching: .any)["developer-callsign"]
        XCTAssertTrue(developer.exists)
        XCTAssertTrue(app.buttons["developer-email"].exists)
        let version = app.descendants(matching: .any)["about-version"]
        XCTAssertTrue(version.exists)
        XCTAssertFalse(app.staticTexts["SwiftUI"].exists)
        XCTAssertFalse(app.staticTexts["Swift 6"].exists)
        XCTAssertFalse(app.staticTexts["iOS 26"].exists)
    }

    @MainActor
    func testConnectedDashboardUsesGeoDerivedMaidenheadWithoutDeferredFixtures() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "dashboard-connected"
        app.launch()

        let callsign = app.descendants(matching: .any)["dashboard-callsign"]
        XCTAssertTrue(callsign.waitForExistence(timeout: 30))
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
        XCTAssertTrue(app.buttons["dashboard-device-selector"].exists)
        XCTAssertFalse(app.buttons["live-activity-entry"].exists)
    }

    @MainActor
    func testConnectedDashboardOpensAndClosesLandscapeFullscreenDashboard() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "dashboard-connected"
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["dashboard-callsign"].waitForExistence(timeout: 30)
        )
        let fullscreen = app.buttons["dashboard-fullscreen-button"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))
        fullscreen.tap()

        let close = app.buttons["dashboard-fullscreen-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BG1ABC"].exists)
        XCTAssertTrue(app.staticTexts["km"].exists)
        let waveform = app.descendants(matching: .any)["dashboard-audio-waveform"]
        XCTAssertTrue(waveform.exists)
        let audioToggle = app.buttons["dashboard-audio-toggle"]
        XCTAssertTrue(audioToggle.exists)
        XCTAssertEqual(audioToggle.value as? String, "已关闭")
        close.tap()

        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard-device-selector"].exists)
    }

    @MainActor
    func testLaunchRestoresLastDeviceAndKeepsNearbyDeviceForManualSelection() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "automatic-connection"
        app.launch()

        let maidenhead = app.descendants(matching: .any)["dashboard-maidenhead-value"]
        XCTAssertTrue(maidenhead.waitForExistence(timeout: 30))
        XCTAssertEqual(maidenhead.value as? String, "PM01rf")

        let selector = app.buttons["dashboard-device-selector"]
        XCTAssertTrue(selector.exists)
        XCTAssertTrue(selector.value as? String == "当前设备 fmo.local，已连接")
        selector.tap()

        let savedDevice = app.buttons["device-row-fmo.local:80"]
        XCTAssertTrue(savedDevice.waitForExistence(timeout: 2))
        XCTAssertEqual(savedDevice.value as? String, "当前设备，已连接")
        XCTAssertTrue(app.buttons["device-row-fmo.local:81"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["断开连接"].exists)
    }

    @MainActor
    func testLiveActivityEntryIsHiddenFromMilestone() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "dashboard-connected"
        app.launch()

        XCTAssertTrue(app.buttons["dashboard-device-selector"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["live-activity-entry"].exists)
        XCTAssertFalse(app.staticTexts["锁屏仪表盘"].exists)
    }

    @MainActor
    func testQSOAutomaticallyShowsCurrentDeviceRecordsAndDetails() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FMO_UI_TEST_SCENARIO"] = "qso-synced"
        app.launch()

        app.buttons["QSO"].tap()
        XCTAssertTrue(app.navigationBars["QSO"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["FMO Test"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["BH0TST"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["PM01AB"].exists)

        app.staticTexts["BH0TST"].tap()
        XCTAssertTrue(app.navigationBars["QSO 详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["网格中心仅表示大致区域"].exists)
        app.swipeUp()
        let relayName = app.staticTexts["qso-relay-name"]
        XCTAssertTrue(relayName.waitForExistence(timeout: 2))
        XCTAssertTrue(relayName.label.contains("示例中继"))
        XCTAssertFalse(app.staticTexts["已验证"].exists)
        XCTAssertFalse(app.staticTexts["SQLite"].exists)
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
