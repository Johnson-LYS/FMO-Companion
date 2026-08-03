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

        app.buttons["手动地址"].tap()
        XCTAssertTrue(app.navigationBars["手动连接"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["主机名或 IPv4"].exists)
        XCTAssertTrue(app.textFields["端口（可选）"].exists)
    }
}
