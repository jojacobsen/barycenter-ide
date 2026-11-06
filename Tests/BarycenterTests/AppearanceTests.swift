import XCTest
import AppKit
@testable import Barycenter

/// The grid-tile appearance settings: defaults and the per-session distinct color.
final class AppearanceTests: XCTestCase {

    func testDefaultsAreUniformBorder() {
        // Fresh keys default to the non-intrusive classic look.
        let d = UserDefaults.standard
        d.removeObject(forKey: "gridTileStyle")
        d.removeObject(forKey: "statusDisplay")
        XCTAssertEqual(AppSettings.shared.gridTileStyle, .uniform)
        XCTAssertEqual(AppSettings.shared.statusDisplay, .border)
    }

    func testDistinctColorIsDeterministicPerID() {
        let id = UUID()
        let a = AppSettings.shared.distinctColor(for: id)
        let b = AppSettings.shared.distinctColor(for: id)
        XCTAssertEqual(a, b, "same session id must always map to the same accent color")
    }

    func testDistinctColorAvoidsStatusColors() {
        // Scan many ids; none of the palette entries may collide with the status
        // colors (green/red/gray), so the accent never reads as a status.
        let forbidden: [NSColor] = [.systemGreen, .systemRed, .systemGray]
        for _ in 0..<200 {
            let c = AppSettings.shared.distinctColor(for: UUID())
            XCTAssertFalse(forbidden.contains(c))
        }
    }
}
