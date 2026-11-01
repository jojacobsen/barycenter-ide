import XCTest
@testable import Barycenter

/// The task-list parser must line up exactly with how marked.js renders checkboxes,
/// so a click in the preview toggles the right line. These cover the tricky cases:
/// bullets, ordered lists, nesting, fenced code, and non-tasks.
final class NotesStoreTests: XCTestCase {

    func testTaskBoxRangeRecognizesBulletAndOrderedMarkers() {
        XCTAssertNotNil(NotesStore.taskBoxRange(in: "- [ ] a"))
        XCTAssertNotNil(NotesStore.taskBoxRange(in: "* [x] a"))
        XCTAssertNotNil(NotesStore.taskBoxRange(in: "+ [X] a"))
        XCTAssertNotNil(NotesStore.taskBoxRange(in: "  - [ ] indented"))
        XCTAssertNotNil(NotesStore.taskBoxRange(in: "1. [ ] ordered"))
        XCTAssertNotNil(NotesStore.taskBoxRange(in: "12) [x] ordered paren"))
    }

    func testTaskBoxRangeRejectsNonTasks() {
        XCTAssertNil(NotesStore.taskBoxRange(in: "just text"))
        XCTAssertNil(NotesStore.taskBoxRange(in: "- plain bullet"))
        XCTAssertNil(NotesStore.taskBoxRange(in: "- foo [ ] not at start"))
        XCTAssertNil(NotesStore.taskBoxRange(in: "-[ ] missing space"))
        XCTAssertNil(NotesStore.taskBoxRange(in: "# [ ] heading"))
        XCTAssertNil(NotesStore.taskBoxRange(in: "1 [ ] no dot"))
    }

    func testTaskLineIndicesSkipFencedCodeAndCountInOrder() {
        let lines = """
        # Todo
        - [ ] first
        1. [x] ordered done
        ```
        - [ ] inside a code fence (not a task)
        ```
        - [ ] last
        - plain bullet
        """.components(separatedBy: "\n")
        // Real tasks: lines 1, 2, 6 (0-based). The fenced one and the plain bullet are excluded.
        XCTAssertEqual(NotesStore.taskLineIndices(in: lines), [1, 2, 6])
    }

    func testTildeFenceIsAlsoSkipped() {
        let lines = """
        ~~~
        - [ ] fenced
        ~~~
        - [ ] real
        """.components(separatedBy: "\n")
        XCTAssertEqual(NotesStore.taskLineIndices(in: lines), [3])
    }
}
