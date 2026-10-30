import XCTest
import AppKit
@testable import Barycenter

/// Covers the New Session project picker: the scanner's ordering/limit, the
/// per-project launch memory round-trip, and the compact relative-time helper.
final class ProjectPickerTests: XCTestCase {

    func testScannerRespectsLimitAndSortsByActivity() {
        let projects = ProjectScanner.recent(limit: 5)
        XCTAssertLessThanOrEqual(projects.count, 5)
        // Most-recently-active first.
        for i in 1..<max(1, projects.count) {
            XCTAssertGreaterThanOrEqual(projects[i - 1].lastActive, projects[i].lastActive)
        }
    }

    func testLaunchMemoryRoundTrip() {
        let cwd = "/tmp/barycenter-test-\(UUID().uuidString)"
        LaunchMemory.remember(cwd: cwd, profileName: "Claude Code",
                              launchCommand: "claude", remoteControl: true)
        let last = LaunchMemory.last(for: cwd)
        XCTAssertEqual(last?.profileName, "Claude Code")
        XCTAssertEqual(last?.launchCommand, "claude")
        XCTAssertEqual(last?.remoteControl, true)

        // Clean up so the user's real memory stays untouched.
        var all = UserDefaults.standard.dictionary(forKey: "launchMemory") as? [String: Any] ?? [:]
        all[cwd] = nil
        UserDefaults.standard.set(all, forKey: "launchMemory")
    }

    func testLaunchMemoryEmptyCommandMapsToNil() {
        let cwd = "/tmp/barycenter-test-\(UUID().uuidString)"
        LaunchMemory.remember(cwd: cwd, profileName: "Shell",
                              launchCommand: nil, remoteControl: false)
        XCTAssertNil(LaunchMemory.last(for: cwd)?.launchCommand)
        var all = UserDefaults.standard.dictionary(forKey: "launchMemory") as? [String: Any] ?? [:]
        all[cwd] = nil
        UserDefaults.standard.set(all, forKey: "launchMemory")
    }

    /// The redesigned New Session sheet must build and lay out without crashing,
    /// and its project list must match the scanner.
    func testNewSessionSheetBuildsAndLaysOut() {
        _ = NSApplication.shared
        let vc = NewSessionSheetController()
        _ = vc.view                                   // triggers loadView()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 440))
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            vc.view.topAnchor.constraint(equalTo: host.topAnchor),
            vc.view.widthAnchor.constraint(equalToConstant: 680),
            vc.view.heightAnchor.constraint(equalToConstant: 440),
        ])
        host.layoutSubtreeIfNeeded()
        if let table = vc.view.subviews.first(where: { $0 is NSStackView })?
            .subviews.compactMap({ ($0 as? NSScrollView)?.documentView as? NSTableView }).first {
            XCTAssertEqual(table.numberOfRows, ProjectScanner.recent().count)
        }
    }

    func testShortRelTime() {
        XCTAssertEqual(shortRelTime(.distantPast), "—")
        XCTAssertEqual(shortRelTime(Date()), "now")
        XCTAssertEqual(shortRelTime(Date(timeIntervalSinceNow: -3 * 3600)), "3h")
        XCTAssertEqual(shortRelTime(Date(timeIntervalSinceNow: -2 * 86400)), "2d")
    }
}
