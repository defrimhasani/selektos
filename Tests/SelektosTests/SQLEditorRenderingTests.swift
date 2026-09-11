import AppKit
import SwiftUI
import XCTest
@testable import Selektos

/// Guards against the line number ruler painting over the document view, which
/// left the editor looking empty even though the text was laid out correctly.
@MainActor
final class SQLEditorRenderingTests: XCTestCase {
    private let sample = "SELECT version();\nSELECT 1 FROM users WHERE id = 3;"

    private func distinctColorCount(of view: NSView) throws -> Int {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        var colors: Set<String> = []
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                colors.insert(String(
                    format: "%.2f,%.2f,%.2f",
                    color.redComponent,
                    color.greenComponent,
                    color.blueComponent
                ))
            }
        }
        return colors.count
    }

    private func mountedEditor() throws -> (NSView, NSScrollView, NSTextView) {
        let host = NSHostingView(rootView: SQLEditor(text: .constant(sample)))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 340)

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()

        func findScrollView(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.documentView is NSTextView { return scroll }
            for subview in view.subviews {
                if let found = findScrollView(subview) { return found }
            }
            return nil
        }

        let scrollView = try XCTUnwrap(findScrollView(host), "SQLEditor did not produce a scroll view")
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView, "scroll view has no text view")
        return (host, scrollView, textView)
    }

    func testEditorTextIsLaidOut() throws {
        let (_, _, textView) = try mountedEditor()
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)

        XCTAssertEqual(textView.string, sample)
        XCTAssertGreaterThan(layoutManager.numberOfGlyphs, 0)
        XCTAssertGreaterThan(layoutManager.usedRect(for: container).height, 0)
    }

    func testEditorTextIsActuallyVisibleInScrollView() throws {
        let (_, scrollView, textView) = try mountedEditor()

        let textViewColors = try distinctColorCount(of: textView)
        let scrollViewColors = try distinctColorCount(of: scrollView)

        XCTAssertGreaterThan(textViewColors, 20, "text view itself drew no text")
        XCTAssertGreaterThan(
            scrollViewColors,
            20,
            "editor rendered blank: text view drew \(textViewColors) colors but the scroll view only \(scrollViewColors). Something is painting over the document view."
        )
    }

    func testLineNumberRulerDoesNotPaintOutsideItsBounds() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        textView.string = sample
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 340))
        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView)
        scrollView.rulersVisible = true

        let ruler = try XCTUnwrap(scrollView.verticalRulerView)
        XCTAssertTrue(ruler.clipsToBounds, "ruler must clip so its background fill cannot cover the editor text")
        XCTAssertGreaterThan(
            try distinctColorCount(of: ruler),
            1,
            "ruler should draw line number labels, not just a flat background"
        )
    }

    func testEditorUsesConfiguredFontSize() throws {
        let defaults = UserDefaults.standard
        let oldValue = defaults.object(forKey: AppPreferences.editorFontSizeKey)
        defaults.set(19.0, forKey: AppPreferences.editorFontSizeKey)
        defer { restore(oldValue, forKey: AppPreferences.editorFontSizeKey) }

        let (_, _, textView) = try mountedEditor()
        let font = try XCTUnwrap(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 19, accuracy: 0.1)
    }

    func testLineNumbersCanBeHidden() throws {
        let defaults = UserDefaults.standard
        let oldValue = defaults.object(forKey: AppPreferences.showLineNumbersKey)
        defaults.set(false, forKey: AppPreferences.showLineNumbersKey)
        defer { restore(oldValue, forKey: AppPreferences.showLineNumbersKey) }

        let (_, scrollView, _) = try mountedEditor()
        XCTAssertFalse(scrollView.hasVerticalRuler)
        XCTAssertFalse(scrollView.rulersVisible)
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
