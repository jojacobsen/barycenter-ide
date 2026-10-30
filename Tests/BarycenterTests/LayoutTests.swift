import XCTest
import AppKit
@testable import Barycenter

/// Layout-Regressionstests: fangen genau die Fehler ab, die uns hier passiert sind —
/// kollabierendes Fenster, verschwindende Session-Liste, unsichtbare Notizen,
/// nicht voll-breite Werkzeug-Ansichten.
final class SidebarLayoutTests: XCTestCase {

    private var savedNotes = false

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared                 // AppKit-Kontext sicherstellen
        savedNotes = AppSettings.shared.showSidebarNotes
    }

    override func tearDown() {
        AppSettings.shared.showSidebarNotes = savedNotes   // echte Nutzer-Einstellung nicht verändern
        super.tearDown()
    }

    /// Baut die Sidebar in einen fest dimensionierten Host und erzwingt das Layout.
    /// (Ein Host mit expliziter Breite/Höhe statt `window.contentView`, sonst kollabiert
    /// die View auf ihre Fitting-Breite und die Messungen werden unbrauchbar.)
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
        vc.test_setNotesExpanded(expanded)   // deterministischer Zustand (nicht aus UserDefaults geerbt)
        host.layoutSubtreeIfNeeded()
        return vc
    }

    /// Die Fitting-Höhe der Sidebar bestimmt (über NSSplitViewController) die Fenster-Mindesthöhe.
    /// Fällt sie unter 480, kann das Fenster beim Start auf die Werkzeugleiste zusammenfallen.
    func testSidebarHasMinimumFittingHeight() {
        let vc = SidebarViewController()
        _ = vc.view
        XCTAssertGreaterThanOrEqual(vc.view.fittingSize.height, 480,
            "Sidebar-Fitting-Höhe < 480 ⇒ Fenster kann kollabieren")
    }

    /// Feature an ⇒ Toggle verfügbar; Liste bleibt sichtbar, auch mit allen Werkzeugen.
    func testNotesToggleAvailableWithAllTools() {
        let vc = layoutSidebar(height: 760, notes: true, tools: [.sessions, .manager, .history])
        XCTAssertGreaterThan(vc.test_sessionsListHeight, 0,
            "Session-Liste verschwindet bei Notizen + allen Werkzeugen")
        XCTAssertTrue(vc.test_notesSectionVisible,
            "Notizen-Toggle nicht verfügbar, obwohl Feature eingeschaltet")
    }

    /// Feature aus ⇒ kein Toggle, keine Box; Liste trotzdem da.
    func testNotesSectionHiddenWhenSettingOff() {
        let vc = layoutSidebar(height: 760, notes: false, tools: [.sessions])
        XCTAssertFalse(vc.test_notesSectionVisible, "Notizen-Bereich sichtbar, obwohl ausgeschaltet")
        XCTAssertGreaterThan(vc.test_sessionsListHeight, 0)
    }

    /// Der Toggle klappt die Textbox auf und wieder zu.
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

    /// Notizen offen + alle Werkzeuge: Liste schrumpft, verschwindet aber nicht.
    func testListKeepsMinimumWhenNotesExpandedWithAllTools() {
        let vc = layoutSidebar(height: 760, notes: true, expanded: true,
                               tools: [.sessions, .manager, .history])
        XCTAssertGreaterThan(vc.test_sessionsListHeight, 20,
            "Liste darf bei offenen Notizen + allen Werkzeugen nicht verschwinden")
    }

    /// Jede Werkzeug-Ansicht muss die volle Panel-Breite haben (sonst verrutschen Liste/Header).
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

    /// Enges Fenster (Minimalhöhe): Notizen schrumpfen, aber nichts bricht/verschwindet hart.
    func testTightPanelDoesNotBreakLayout() {
        let vc = layoutSidebar(height: 520, notes: true,
                               tools: [.sessions, .manager, .history])
        XCTAssertGreaterThanOrEqual(vc.test_sessionsListHeight, 0)
        XCTAssertGreaterThan(vc.test_panelWidth, 0)
        XCTAssertTrue(vc.test_notesSectionVisible, "Notizen auch bei engem Panel sichtbar")
    }
}
