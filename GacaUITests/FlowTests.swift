import XCTest

/// End-to-end flows against a throwaway local gaca-api plus tools/fake_hermes.py, seeded by
/// tools/e2e.sh. Skipped unless the runner provides GACA_E2E_BASE (e2e.sh passes it as
/// TEST_RUNNER_GACA_E2E_BASE).
final class FlowTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard let base = env["GACA_E2E_BASE"], let token = env["GACA_E2E_TOKEN"] else {
            throw XCTSkip("No local API — run tools/e2e.sh")
        }
        app = XCUIApplication()
        app.launchEnvironment["GACA_API_BASE"] = base
        app.launchEnvironment["GACA_UITEST_RESET"] = "1"
        app.launchEnvironment["GACA_UITEST_TOKEN"] = token
        app.launch()
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 15), "should open on the Chat tab, paired")
    }

    /// Any element whose accessibility label contains `text` (SwiftUI often folds a row's
    /// texts into one button label).
    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testKeyboardCanBePutAwayOnChatHome() {
        let field = app.textFields["composer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "software keyboard is up")
        shot("08-typing-done-in-nav-bar")
        app.buttons["composer.done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Done puts the keyboard away")
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 5), "tab bar reachable again")
    }

    func testNewChatStreamsReplyWithActivityAndPageCard() {
        // Pick the second crew member and send from the home composer.
        XCTAssertTrue(app.buttons["Chat with Toolshed"].waitForExistence(timeout: 10))
        app.buttons["Chat with Toolshed"].tap()
        shot("01-chat-home")
        let field = app.textFields["composer.field"]
        field.tap()
        field.typeText("slow please check the disk and make a page")
        app.buttons["composer.send"].tap()

        // Live row while the fake agent runs its tools.
        XCTAssertTrue(app.staticTexts["Using web_search"].waitForExistence(timeout: 10), "live activity row")
        shot("02-thread-live")

        // Finished: the API's activity summary, the prose reply, and the page card.
        let activity = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Used web_search, terminal 2×'")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 30), "activity chip from the API")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Want me to prep anything'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Disk usage'")).firstMatch.exists, "page card")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'gaca://'")).firstMatch.exists, "raw link stripped")
        shot("03-thread-done")

        activity.tap()
        XCTAssertTrue(app.staticTexts["web_search"].waitForExistence(timeout: 3))
        shot("04-activity-expanded")

        // The page opens in the viewer and renders.
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Disk usage'")).firstMatch.tap()
        XCTAssertTrue(app.webViews.staticTexts["E2E page body"].waitForExistence(timeout: 15), "artifact page rendered")
        shot("05-artifact")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Back home, the chat is in Recent.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'slow please check the disk'")).firstMatch.waitForExistence(timeout: 10))
        shot("06-home-recent")
    }

    func testFailedRunShowsError() {
        let field = app.textFields["composer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("please fail")
        app.buttons["composer.send"].tap()
        XCTAssertTrue(app.staticTexts["The fake agent was asked to fail."].waitForExistence(timeout: 20))
        shot("07-run-failed")
    }

    func testAlertToChatAndTriage() {
        app.tabBars.buttons["Inbox"].tap()
        let alert = app.staticTexts["Disk usage on gaca-pi is at 92%"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        shot("08-inbox")
        alert.tap()
        XCTAssertTrue(app.staticTexts["Prune old Docker images"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["used"].exists, "data rows from the API")
        shot("09-alert-detail")

        // Take it to chat: lands in the thread with a draft, alert card pinned on top.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chat with'")).firstMatch.tap()
        let field = app.textFields["composer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'URGENT ALERT'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse((field.value as? String ?? "").isEmpty, "draft prefilled by the API")
        shot("10-alert-chat-draft")
        app.buttons["composer.send"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Used web_search'")).firstMatch.waitForExistence(timeout: 30))
        shot("11-alert-chat-reply")
    }

    func testSwipeToHandleAlert() {
        app.tabBars.buttons["Inbox"].tap()
        let row = app.staticTexts["Nightly backup finished"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeRight()
        app.buttons["Handled"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10))
        app.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Nightly backup finished"].waitForExistence(timeout: 10))
    }

    func testDelegationTodaySkillsAndCrew() {
        // New delegation from the Inbox.
        app.tabBars.buttons["Inbox"].tap()
        app.buttons["Start a delegation"].tap()
        let text = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields["What should your crew do?"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("Watch flight prices to Lisbon")
        shot("12-delegation")
        app.buttons["Start"].tap()
        app.buttons["Delegated"].tap()
        XCTAssertTrue(app.staticTexts["Watch flight prices to Lisbon"].waitForExistence(timeout: 10))

        // Today shows the seeded briefing.
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'A quiet Saturday'")).firstMatch.waitForExistence(timeout: 10))
        shot("13-today")

        // Skills come live from the (fake) Hermes, behind the composer's sparkle button.
        app.tabBars.buttons["Chat"].tap()
        let skillsButton = app.buttons["composer.skills"]
        XCTAssertTrue(skillsButton.waitForExistence(timeout: 10))
        skillsButton.tap()
        XCTAssertTrue(app.staticTexts["disk-report"].waitForExistence(timeout: 10))
        shot("14-skills")
        app.staticTexts["disk-report"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "composer.field").firstMatch
        XCTAssertEqual(field.value as? String, "/disk-report ")
        if app.buttons["composer.done"].exists { app.buttons["composer.done"].tap() }

        // Crew detail via Settings.
        app.buttons["Settings"].firstMatch.tap()
        if !element(containing: "Connected").waitForExistence(timeout: 10) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "tree-settings"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(element(containing: "Connected").exists)
        shot("15-settings")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Toolshed' AND label CONTAINS 'port'")).firstMatch.tap()
        XCTAssertTrue(element(containing: "SCHEDULED").waitForExistence(timeout: 10))
        app.swipeUp()
        let job = element(containing: "Weekly Docker prune")
        if !job.waitForExistence(timeout: 10) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "tree-crew-detail"
            tree.lifetime = .keepAlways
            add(tree)
            shot("crew-detail-failure")
        }
        XCTAssertTrue(job.exists)
        shot("16-crew-detail")
    }

    func testArtifactsListAndViewer() {
        app.tabBars.buttons["Artifacts"].tap()
        XCTAssertTrue(app.staticTexts["Disk usage"].waitForExistence(timeout: 10))
        shot("17-artifacts")
        app.staticTexts["Disk usage"].tap()
        XCTAssertTrue(app.webViews.staticTexts["E2E page body"].waitForExistence(timeout: 15))
        // The page's data call went through the API bridge and came back.
        XCTAssertTrue(app.webViews.staticTexts["count: 1"].waitForExistence(timeout: 10), "window.app bridge round-trip")
        shot("18-artifact-bridge")
    }
}
