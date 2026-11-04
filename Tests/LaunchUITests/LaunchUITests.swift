import XCTest

final class LaunchUITests: XCTestCase {
    func testManualAOTActionReachesRealGuestLoggingImport() {
        let app = XCUIApplication()
        app.launch()
        let action = app.buttons["run-aot-bootstrap"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["aot-result"].exists, "The AOT image must not run automatically at startup")
        action.tap()
        let result = app.staticTexts["aot-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        XCTAssertTrue(result.label.contains("host_call"))
        XCTAssertTrue(app.staticTexts["aot-message"].label.contains("[nx-mem] guest arena 04900000..04a00000 (1 MB)"))
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testAppReachesIdleScreenAndSurvivesFirstLaunchAndRelaunch() {
        let app = XCUIApplication()
        for _ in 0..<2 {
            app.launch()
            XCTAssertTrue(app.buttons["1. Signed ARM64 baseline"].waitForExistence(timeout: 15),
                          "App must reach its idle screen before a native experiment is requested")
            XCTAssertTrue(app.buttons["2. Low-memory callback experiment"].exists)
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertFalse(app.wait(for: .notRunning, timeout: 2),
                           "App must not exit immediately after reaching its screen")
            app.terminate()
        }
    }
}
