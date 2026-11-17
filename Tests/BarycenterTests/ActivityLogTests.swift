import XCTest
@testable import Barycenter

/// The activity timeline: parsing hook payloads (also when cut mid-value) into events.
final class ActivityLogTests: XCTestCase {

    private func session(cwd: String = "/tmp/proj") -> Session {
        Session(title: "t", cwd: cwd, launchCommand: "claude", profileName: "Claude Code")
    }

    private func write(_ lines: [String], for s: Session) {
        let text = lines.joined(separator: "\n") + "\n"
        FileManager.default.createFile(atPath: ActivityLog.path(for: s.id), contents: Data(text.utf8))
    }

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(
            atPath: (ActivityLog.path(for: UUID()) as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
    }

    func testFieldExtractsAndUnescapes() {
        let raw = #"{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo \"hi\"\nls"}}"#
        XCTAssertEqual(ActivityLog.field("tool_name", in: raw), "Bash")
        XCTAssertEqual(ActivityLog.field("command", in: raw), "echo \"hi\"\nls")
        XCTAssertNil(ActivityLog.field("missing", in: raw))
    }

    func testFieldSurvivesCutLine() {
        // Lines are cut at maxLineChars — possibly mid-string or mid-escape.
        let raw = #"{"hook_event_name":"UserPromptSubmit","prompt":"fix the bug in \"#
        XCTAssertEqual(ActivityLog.field("prompt", in: raw), "fix the bug in ")
    }

    func testEventsAreParsedNewestFirstWithRelativePaths() {
        let s = session()
        write([
            "1000\t" + #"{"hook_event_name":"BarycenterStart","profile":"Claude Code","resume":false}"#,
            "1001\t" + #"{"hook_event_name":"UserPromptSubmit","prompt":"add a test"}"#,
            "1002\t" + #"{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/tmp/proj/Sources/A.swift","old_string":"x"}}"#,
            "1003\t" + #"{"hook_event_name":"Stop"}"#,
        ], for: s)
        let ev = ActivityLog.events(for: s)
        XCTAssertEqual(ev.map(\.kind), [.done, .tool, .prompt, .started])
        XCTAssertEqual(ev[1].label, "Edit")
        XCTAssertEqual(ev[1].detail, "Sources/A.swift")
        XCTAssertEqual(ev[2].detail, "add a test")
    }

    func testConsecutiveDuplicatesCollapse() {
        let s = session()
        let read = #"{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"swift build"}}"#
        write(["1\t" + read, "2\t" + read, "3\t" + read], for: s)
        let ev = ActivityLog.events(for: s)
        XCTAssertEqual(ev.count, 1)
        XCTAssertEqual(ev[0].count, 3)
    }

    func testMCPToolLabelAndGarbageLinesIgnored() {
        let s = session()
        write([
            "not a line",
            "5\t" + #"{"hook_event_name":"PreToolUse","tool_name":"mcp__github__create_pr","tool_input":{"title":"Fix it"}}"#,
        ], for: s)
        let ev = ActivityLog.events(for: s)
        XCTAssertEqual(ev.count, 1)
        XCTAssertEqual(ev[0].label, "github · create_pr")
        XCTAssertEqual(ev[0].detail, "Fix it")
    }

    func testTransferMovesHistory() {
        let a = session(), b = session()
        write(["1\t" + #"{"hook_event_name":"Stop"}"#], for: a)
        ActivityLog.transfer(from: a.id, to: b.id)
        XCTAssertEqual(ActivityLog.events(for: b).count, 1)
        XCTAssertTrue(ActivityLog.events(for: a).isEmpty)
    }
}
