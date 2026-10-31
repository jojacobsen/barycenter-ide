import XCTest
import AppKit
@testable import Barycenter

/// Layout regression tests: catch exactly the bugs that happened to us here —
/// collapsing window, disappearing session list, invisible notes,
/// tool views that aren't full width.
final class SidebarLayoutTests: XCTestCase {

    private var savedNotes = false

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared                 // ensure the AppKit context
        savedNotes = AppSettings.shared.showSidebarNotes
    }

    override func tearDown() {
        AppSettings.shared.showSidebarNotes = savedNotes   // don't change the real user setting
        super.tearDown()
    }

    /// Builds the sidebar into a fixed-size host and forces layout.
    /// (A host with an explicit width/height instead of `window.contentView`, otherwise the
    /// view collapses to its fitting width and the measurements become useless.)
    private func layoutSidebar(height: CGFloat, width: CGFloat = 320,
                               notes: Bool, expanded: Bool = false,
                               tools: [Tool]) -> SidebarViewController {
        AppSettings.shared.showSidebarNotes = notes
        let vc = SidebarViewController()
        _ = vc.view
        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            vc.view.topAnchor.constraint(equalTo: host.topAnchor),
            vc.view.widthAnchor.constraint(equalToConstant: width),
            vc.view.heightAnchor.constraint(equalToConstant: height),
        ])
        vc.test_showTools(tools)
        vc.test_setNotesExpanded(expanded)   // deterministic state (not inherited from UserDefaults)
        host.layoutSubtreeIfNeeded()
        return vc
    }

    /// The sidebar's fitting height determines (via NSSplitViewController) the window's minimum height.
    /// If it drops below 480, the window can collapse to the tool bar on launch.
    func testSidebarHasMinimumFittingHeight() {
        let vc = SidebarViewController()
        _ = vc.view
        XCTAssertGreaterThanOrEqual(vc.view.fittingSize.height, 480,
            "Sidebar-Fitting-Höhe < 480 ⇒ Fenster kann kollabieren")
    }

    /// Feature on ⇒ toggle available; list stays visible, even with all tools.
    func testNotesToggleAvailableWithAllTools() {
        let vc = layoutSidebar(height: 760, notes: true, tools: [.sessions, .manager, .history])
        XCTAssertGreaterThan(vc.test_sessionsListHeight, 0,
            "Session-Liste verschwindet bei Notizen + allen Werkzeugen")
        XCTAssertTrue(vc.test_notesSectionVisible,
            "Notizen-Toggle nicht verfügbar, obwohl Feature eingeschaltet")
    }

    /// Feature off ⇒ no toggle, no box; list still there.
    func testNotesSectionHiddenWhenSettingOff() {
        let vc = layoutSidebar(height: 760, notes: false, tools: [.sessions])
        XCTAssertFalse(vc.test_notesSectionVisible, "Notizen-Bereich sichtbar, obwohl ausgeschaltet")
        XCTAssertGreaterThan(vc.test_sessionsListHeight, 0)
    }

    /// The toggle expands the text box and collapses it again.
    func testNotesToggleExpandsAndCollapsesBox() {
        AppSettings.shared.showSidebarNotes = true
        let vc = SidebarViewController()
        _ = vc.view
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 760))
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            vc.view.topAnchor.constraint(equalTo: host.topAnchor),
            vc.view.widthAnchor.constraint(equalToConstant: 320),
            vc.view.heightAnchor.constraint(equalToConstant: 760),
        ])
        vc.test_showTools([.sessions])

        vc.test_setNotesExpanded(false)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(vc.test_notesSectionVisible, "Toggle muss auch eingeklappt sichtbar sein")
        XCTAssertFalse(vc.test_notesBoxVisible, "Box darf eingeklappt nicht sichtbar sein")

        vc.test_setNotesExpanded(true)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(vc.test_notesBoxVisible, "Box muss nach dem Aufklappen sichtbar sein")
    }

    /// Notes open + all tools: list shrinks but doesn't disappear.
    func testListKeepsMinimumWhenNotesExpandedWithAllTools() {
        let vc = layoutSidebar(height: 760, notes: true, expanded: true,
                               tools: [.sessions, .manager, .history])
        XCTAssertGreaterThan(vc.test_sessionsListHeight, 20,
            "Liste darf bei offenen Notizen + allen Werkzeugen nicht verschwinden")
    }

    /// Every tool view must have the full panel width (otherwise list/header shift).
    func testAllToolViewsSpanFullPanelWidth() {
        let vc = layoutSidebar(height: 760, width: 320, notes: true,
                               tools: [.sessions, .manager, .history])
        let panel = vc.test_panelWidth
        XCTAssertGreaterThan(panel, 0)
        let widths = vc.test_toolViewWidths
        XCTAssertEqual(widths.count, 3, "Erwarte drei Werkzeug-Ansichten")
        for w in widths {
            XCTAssertEqual(w, panel, accuracy: 0.5,
                "Werkzeug-Ansicht nicht auf voller Panel-Breite")
        }
    }

    /// Narrow window (minimum height): notes shrink, but nothing breaks/disappears hard.
    func testTightPanelDoesNotBreakLayout() {
        let vc = layoutSidebar(height: 520, notes: true,
                               tools: [.sessions, .manager, .history])
        XCTAssertGreaterThanOrEqual(vc.test_sessionsListHeight, 0)
        XCTAssertGreaterThan(vc.test_panelWidth, 0)
        XCTAssertTrue(vc.test_notesSectionVisible, "Notizen auch bei engem Panel sichtbar")
    }
}
