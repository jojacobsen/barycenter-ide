import XCTest
import AppKit
@testable import Barycenter

/// Verifies the status mapping used by the menu bar (and the Dock alarm):
/// "needs you", dot color and status text per session state.
final class MenuBarStatusTests: XCTestCase {

    /// A shell session (no Claude) follows `status` directly, without a live agent query.
    private func shellSession() -> Session {
        Session(title: "shell", cwd: NSTemporaryDirectory(),
                launchCommand: nil, profileName: "Shell")
    }

    func testRunningIsNotAttention() {
        let s = shellSession()
        s.status = .running
        XCTAssertFalse(s.needsAttention)
        XCTAssertEqual(s.menuStatusColor, .systemGreen)
        XCTAssertEqual(s.menuStatusText, L("läuft"))
    }

    func testAttentionIsFlaggedAndRed() {
        let s = shellSession()
        s.status = .attention
        XCTAssertTrue(s.needsAttention, "attention must count as 'needs you'")
        XCTAssertEqual(s.menuStatusColor, .systemRed)
        XCTAssertEqual(s.menuStatusText, L("braucht dich"))
    }

    func testDoneIsNotAttention() {
        let s = shellSession()
        s.status = .done
        XCTAssertFalse(s.needsAttention)
        XCTAssertEqual(s.menuStatusText, L("beendet"))
    }
}
