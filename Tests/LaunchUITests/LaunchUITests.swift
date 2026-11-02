import XCTest

final class LaunchUITests: XCTestCase {
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
