import AppKit
import SwiftUI

struct SQLEditor: NSViewRepresentable {
    @Binding var text: String
    @AppStorage(AppPreferences.editorFontSizeKey) private var fontSize = 14.0
    @AppStorage(AppPreferences.showLineNumbersKey) private var showLineNumbers = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, fontSize: fontSize)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = SQLTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isFieldEditor = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.selectedTextColor
        ]
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        textView.minSize = NSSize(width: 0, height: 400)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.string = text

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.rulersVisible = showLineNumbers
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView)

        context.coordinator.textView = textView
        context.coordinator.highlightSyntax()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let fontChanged = context.coordinator.fontSize != fontSize
        context.coordinator.fontSize = fontSize
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.rulersVisible = showLineNumbers

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSIntersectionRange(selection, NSRange(location: 0, length: text.utf16.count)))
            context.coordinator.highlightSyntax()
        } else if fontChanged {
            context.coordinator.highlightSyntax()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?
        var fontSize: Double

        init(text: Binding<String>, fontSize: Double) {
            _text = text
            self.fontSize = fontSize
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
            highlightSyntax()
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.refresh()
        }

        func highlightSyntax() {
            guard let textStorage = textView?.textStorage else { return }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            let baseFont = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.tabStops = []
            paragraphStyle.defaultTabInterval = 32
            textStorage.beginEditing()
            textStorage.setAttributes([
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ], range: fullRange)

            apply(pattern: #"\b(SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|FULL|ON|AS|AND|OR|NOT|NULL|IS|IN|LIKE|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|ALTER|DROP|TABLE|VIEW|DISTINCT|UNION|ALL|CASE|WHEN|THEN|ELSE|END|ASC|DESC|INTERVAL)\b"#, color: SQLColors.keyword, font: .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .semibold), in: textStorage)
            apply(pattern: #"\b(CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|COUNT|SUM|AVG|MIN|MAX|COALESCE|NOW)\b"#, color: SQLColors.function, in: textStorage)
            apply(pattern: #"'(?:''|[^'])*'"#, color: SQLColors.string, in: textStorage)
            apply(pattern: #"\b\d+(?:\.\d+)?\b"#, color: SQLColors.number, in: textStorage)
            apply(pattern: #"--[^\n]*|/\*[\s\S]*?\*/"#, color: SQLColors.comment, in: textStorage)
            textStorage.endEditing()
        }

        private func apply(
            pattern: String,
            color: NSColor,
            font: NSFont? = nil,
            in storage: NSTextStorage
        ) {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
            let range = NSRange(location: 0, length: storage.length)
            expression.enumerateMatches(in: storage.string, range: range) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
                if let font {
                    storage.addAttribute(.font, value: font, range: match.range)
                }
            }
        }
    }
}

final class SQLTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        guard isEditable, isSelectable else { return false }
        return super.becomeFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window.firstResponder == nil else { return }
        window.makeFirstResponder(self)
    }
}

private enum SQLColors {
    static let keyword = adaptive(light: NSColor(calibratedRed: 0.45, green: 0.16, blue: 0.68, alpha: 1), dark: NSColor(calibratedRed: 0.78, green: 0.53, blue: 1, alpha: 1))
    static let function = adaptive(light: NSColor(calibratedRed: 0.04, green: 0.32, blue: 0.72, alpha: 1), dark: NSColor(calibratedRed: 0.35, green: 0.68, blue: 1, alpha: 1))
    static let string = adaptive(light: NSColor(calibratedRed: 0.72, green: 0.25, blue: 0.08, alpha: 1), dark: NSColor(calibratedRed: 1, green: 0.62, blue: 0.32, alpha: 1))
    static let number = adaptive(light: NSColor(calibratedRed: 0, green: 0.43, blue: 0.4, alpha: 1), dark: NSColor(calibratedRed: 0.28, green: 0.82, blue: 0.74, alpha: 1))
    static let comment = adaptive(light: NSColor(calibratedWhite: 0.38, alpha: 1), dark: NSColor(calibratedWhite: 0.67, alpha: 1))

    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
        clipsToBounds = true

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification, object: textView)
        center.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: textView.enclosingScrollView?.contentView)
        textView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func refresh() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        NSColor.controlBackgroundColor.setFill()
        rect.intersection(bounds).fill()

        let visibleRect = textView.enclosingScrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let string = textView.string as NSString
        var lineNumber = 1
        if glyphRange.location > 0 {
            lineNumber += string.substring(to: layoutManager.characterIndexForGlyph(at: glyphRange.location))
                .reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        var glyphIndex = glyphRange.location
        let textOriginY = convert(NSPoint.zero, from: textView).y + textView.textContainerOrigin.y

        while glyphIndex < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange,
                withoutAdditionalLayout: true
            )
            let label = String(lineNumber) as NSString
            let labelSize = label.size(withAttributes: attributes)
            let y = textOriginY + lineRect.minY + (lineRect.height - labelSize.height) / 2
            label.draw(at: NSPoint(x: ruleThickness - labelSize.width - 9, y: y), withAttributes: attributes)

            glyphIndex = NSMaxRange(lineGlyphRange)
            lineNumber += 1
        }
    }
}
