import XCTest
import AppKit
@testable import Barycenter

/// Sichert das Status-Mapping ab, das die Menüleiste (und der Dock-Alarm) nutzen:
/// „braucht dich", Punktfarbe und Statustext je Session-Zustand.
final class MenuBarStatusTests: XCTestCase {

    /// Shell-Session (kein Claude) folgt direkt `status` — ohne Live-Agent-Abfrage.
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
        XCTAssertTrue(s.needsAttention, "attention muss als 'braucht dich' zaehlen")
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
