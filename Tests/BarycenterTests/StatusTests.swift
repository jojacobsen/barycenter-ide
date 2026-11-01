import XCTest
import AppKit
@testable import Barycenter

/// The single `displayState` drives the dot, the tile border and the labels, so its
/// text/color/needsYou mapping must stay correct. (Shell sessions, no live Claude info.)
final class StatusTests: XCTestCase {

    private func shellSession() -> Session {
        Session(title: "t", cwd: NSHomeDirectory(), launchCommand: nil, profileName: "Shell")
    }

    func testRunningIsGreenAndNotNeedingYou() {
        let s = shellSession()
        s.status = .running
        XCTAssertEqual(s.displayState.color, .systemGreen)
        XCTAssertFalse(s.displayState.needsYou)
    }

    func testAttentionIsRedAndNeedsYou() {
        let s = shellSession()
        s.status = .attention
        XCTAssertEqual(s.displayState.color, .systemRed)
        XCTAssertTrue(s.displayState.needsYou)
    }

    func testDoneIsGrayAndNotNeedingYou() {
        let s = shellSession()
        s.status = .done
        XCTAssertEqual(s.displayState.color, .systemGray)
        XCTAssertFalse(s.displayState.needsYou)
    }

    // MARK: - Launch failure hint (#6)

    func testLaunchFailureHintOnFastNonZeroExit() {
        let s = Session(title: "t", cwd: NSHomeDirectory(), launchCommand: "nonexistent-cli", profileName: "Custom")
        s.exitCode = 127
        s.endedAt = s.startedAt.addingTimeInterval(1)
        XCTAssertNotNil(s.launchFailureHint)
        XCTAssertTrue(s.launchFailureHint?.contains("nonexistent-cli") ?? false)
    }

    func testNoHintOnCleanExit() {
        let s = Session(title: "t", cwd: NSHomeDirectory(), launchCommand: "claude", profileName: "Claude Code")
        s.exitCode = 0
        s.endedAt = s.startedAt.addingTimeInterval(1)
        XCTAssertNil(s.launchFailureHint)
    }

    func testNoHintForPlainShell() {
        let s = shellSession()
        s.exitCode = 1
        s.endedAt = s.startedAt.addingTimeInterval(1)
        XCTAssertNil(s.launchFailureHint)   // no launch command -> not a "failed to start"
    }
}
