import AppKit
import XCTest
@testable import Selektos

@MainActor
final class SQLEditorTests: XCTestCase {
    func testEditorAcceptsKeyboardInputAsFirstResponder() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let editor = SQLTextView(frame: window.contentView!.bounds)
        editor.isEditable = true
        editor.isSelectable = true
        editor.string = "SELECT "
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertTrue(window.firstResponder === editor)

        editor.insertText("1;", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.string, "SELECT 1;")
        window.orderOut(nil)
    }
}
