import XCTest

/// The iPad version of the walkthrough: taps through the app and records a
/// screenshot and the app's state at every step. Asserts nothing; CI
/// publishes the steps to the ui-test-results branch (ipad/).
final class PadWalkthroughTests: XCTestCase {
    private let app = XCUIApplication()
    private var step = 0
    private var log = ""

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: log)
        attachment.name = "ipad-log.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWalkthrough() {
        wait(10)
        record("home")

        tap(app.buttons["Details"].firstMatch, "Details")
        wait(4)
        record("detail")
        app.swipeUp()
        wait(2)
        record("detail-scrolled")
        app.swipeDown()
        wait(1)

        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play'")).firstMatch, "Play")
        wait(30)
        record("player")
        app.tap()
        wait(1)
        record("player-controls")
        if app.buttons["Episodes"].exists {
            tap(app.buttons["Episodes"], "Episodes")
            wait(4)
            record("episodes-sheet")
            tap(app.buttons["Done"], "Done")
            wait(1)
        }
        tap(app.buttons["Close"], "Close")
        wait(2)
        record("back-from-player")

        for tab in ["Movies", "TV Shows", "Search"] {
            tap(app.buttons[tab].firstMatch, tab)
            wait(6)
            record(tab.lowercased().replacingOccurrences(of: " ", with: "-"))
        }

        XCUIDevice.shared.orientation = .portrait
        tap(app.buttons["Home"].firstMatch, "Home")
        wait(4)
        record("home-portrait")
    }

    // MARK: - Helpers

    private func tap(_ element: XCUIElement, _ name: String) {
        if element.waitForExistence(timeout: 5), element.isHittable {
            element.tap()
            log += "  tapped \(name)\n"
        } else {
            log += "  COULD NOT TAP \(name) (exists: \(element.exists))\n"
        }
    }

    private func wait(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func record(_ label: String) {
        step += 1
        let name = "ipad-\(String(format: "%02d", step))-\(label)"
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let state = app.state == .runningForeground ? "running" : "NOT RUNNING (state \(app.state.rawValue))"
        log += "\(name): app \(state)\n"
    }
}
