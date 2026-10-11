import XCTest

/// First run: pair with the code `gaca-api pair` printed (typed — the simulator has no camera,
/// so the screen opens in typing mode). tools/e2e.sh issues the code.
final class PairingTests: XCTestCase {
    func testPairWithTypedAddressAndCode() throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["GACA_E2E_SERVER"], let code = env["GACA_E2E_CODE"] else {
            throw XCTSkip("No local API — run tools/e2e.sh")
        }
        let app = XCUIApplication()
        app.launchEnvironment["GACA_UITEST_RESET"] = "1"
        app.launch()

        let address = app.textFields["pair.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10), "unpaired app opens on the pairing screen")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "00-pairing"
        shot.lifetime = .keepAlways
        add(shot)

        // A wrong code is refused with the server's reason and nothing is saved.
        address.tap()
        address.typeText(server)
        let codeField = app.textFields["pair.code"]
        codeField.tap()
        codeField.typeText("WRONG-CODE")
        app.buttons["pair.submit"].tap()
        XCTAssertTrue(app.textFields["pair.code"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Chat"].waitForExistence(timeout: 3))

        // The real code pairs and lands on Chat.
        codeField.tap()
        codeField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 16))
        codeField.typeText(code)
        app.buttons["pair.submit"].tap()
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 15), "paired and on the Chat tab")

        // Settings › Disconnect returns to pairing.
        app.buttons["Settings"].firstMatch.tap()
        let disconnect = app.buttons["Disconnect from this server"]
        for _ in 0..<4 where !disconnect.isHittable { app.swipeUp() }
        disconnect.tap()
        app.buttons["Disconnect"].firstMatch.tap()
        XCTAssertTrue(app.textFields["pair.address"].waitForExistence(timeout: 10), "back on the pairing screen")
    }
}
