import XCTest

/// Drives the app with the Siri Remote the way a person would and records a
/// screenshot, the focused element and the app's state at every step. It
/// asserts nothing: CI publishes the steps (ui-test-results branch) so a
/// person or agent can see what each screen actually looks like.
final class WalkthroughTests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var step = 0
    private var log = ""

    override func setUp() {
        continueAfterFailure = true
        app.launch()
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: log)
        attachment.name = "\(name.components(separatedBy: " ").last?.dropLast() ?? "test")-log.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Home → a title → Play → back out mid-close and play again → back home.
    func test1Playback() {
        wait(10)
        record("home")
        press(.down, times: 2)
        record("home-down2")
        press(.select)
        wait(4)
        record("detail")
        press(.select)
        wait(3)
        record("player-loading")
        wait(25)
        record("player-after-25s")
        press(.menu)
        wait(0.4)
        press(.select)
        wait(1)
        record("replay-while-closing")
        wait(15)
        record("replay-after-15s")
        press(.menu)
        wait(2)
        record("back-on-detail")
        press(.menu)
        wait(2)
        record("back-on-home")
    }

    /// Sidebar → TV Shows → a show → change season → episodes → Search.
    func test2SidebarAndShow() {
        wait(10)
        press(.left, times: 3)
        wait(1)
        record("sidebar-open")
        press(.down)
        wait(1)
        record("sidebar-movies")
        press(.down)
        wait(1)
        record("sidebar-tv")
        press(.right)
        wait(6)
        record("tv-content")
        press(.select)
        wait(5)
        record("show-detail")
        press(.down)
        wait(1)
        record("show-down1")
        press(.down)
        wait(1)
        record("show-down2")
        press(.right)
        press(.select)
        wait(4)
        record("show-season-changed")
        press(.down)
        wait(1)
        record("show-episodes")
        press(.menu)
        wait(2)
        record("back-from-show")
        press(.left, times: 3)
        wait(1)
        record("sidebar-again")
        press(.down, times: 3)
        press(.select)
        wait(3)
        record("search")
    }

    /// TV Shows → a show → Play → swipe down for the info panel → Episodes tab.
    func test3EpisodePlayer() {
        wait(10)
        press(.left, times: 3)
        press(.down, times: 2)
        press(.right)
        wait(6)
        press(.select)
        wait(5)
        record("show-detail")
        press(.select)
        wait(30)
        record("episode-playing")
        press(.down)
        wait(2)
        record("info-panel")
        press(.right)
        wait(2)
        record("info-panel-right")
        press(.right)
        wait(2)
        record("info-panel-right2")
        press(.down)
        wait(3)
        record("episodes-tab-cards")
        press(.menu)
        wait(2)
        record("panel-closed")
    }

    // MARK: - Helpers

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: 0.6)
        }
        log += "  pressed \(button.name) x\(times)\n"
    }

    private func wait(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func record(_ label: String) {
        step += 1
        let test = name.contains("test1") ? "1" : name.contains("test2") ? "2" : "3"
        let prefix = "\(test)-\(String(format: "%02d", step))-\(label)"

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = prefix
        shot.lifetime = .keepAlways
        add(shot)

        let state = app.state == .runningForeground ? "running" : "NOT RUNNING (state \(app.state.rawValue))"
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let focus = focused.exists
            ? "\(focused.elementType.rawValue) '\(focused.label)' \(focused.identifier) at \(focused.frame)"
            : "nothing"
        log += "\(prefix): app \(state); focus: \(focus)\n"
    }
}

private extension XCUIRemote.Button {
    var name: String {
        switch self {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .select: return "select"
        case .menu: return "menu"
        case .playPause: return "playPause"
        @unknown default: return "button \(rawValue)"
        }
    }
}
