import AppKit
import SwiftUI

struct SQLCompletionCatalog: Equatable {
    let schemas: [DatabaseSchema]
    let focusedSchema: String?

    static let empty = SQLCompletionCatalog()

    init(schemas: [DatabaseSchema] = [], focusedSchema: String? = nil) {
        self.schemas = schemas
        self.focusedSchema = focusedSchema
    }
}

private enum SQLVocabulary {
    static let keywords = [
        "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER",
        "FULL", "CROSS", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "IN",
        "LIKE", "ILIKE", "BETWEEN", "EXISTS", "GROUP", "BY", "ORDER", "HAVING",
        "LIMIT", "OFFSET", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "ALTER", "DROP", "TABLE", "VIEW", "DISTINCT", "UNION", "ALL",
        "CASE", "WHEN", "THEN", "ELSE", "END", "ASC", "DESC", "INTERVAL", "WITH",
        "RECURSIVE", "RETURNING", "CONFLICT", "DO", "NOTHING", "PRIMARY", "KEY",
        "FOREIGN", "REFERENCES", "DEFAULT", "CHECK", "UNIQUE", "INDEX", "DATABASE",
        "SCHEMA", "TRUNCATE", "GRANT", "REVOKE", "EXPLAIN", "ANALYZE", "USING",
        "OVER", "PARTITION", "WINDOW", "FILTER", "NULLS", "FIRST", "LAST", "FETCH",
        "ONLY", "LATERAL"
    ]

    static let functions = [
        "AVG", "COALESCE", "COUNT", "CURRENT_DATE", "CURRENT_TIME",
        "CURRENT_TIMESTAMP", "LOWER", "MAX", "MIN", "NOW", "ROUND", "SUM",
        "UPPER", "VERSION"
    ]

    static let keywordSet = Set(keywords)
    static let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
    static let functionPattern = "\\b(" + functions.joined(separator: "|") + ")\\b"
}

struct SQLEditor: NSViewRepresentable {
    @Binding var text: String
    let completionCatalog: SQLCompletionCatalog
    @AppStorage(AppPreferences.editorFontSizeKey) private var fontSize = 14.0
    @AppStorage(AppPreferences.showLineNumbersKey) private var showLineNumbers = true

    init(
        text: Binding<String>,
        completionCatalog: SQLCompletionCatalog = .empty
    ) {
        _text = text
        self.completionCatalog = completionCatalog
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            fontSize: fontSize,
            completionCatalog: completionCatalog
        )
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
        context.coordinator.completionCatalog = completionCatalog
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
        var completionCatalog: SQLCompletionCatalog
        private var completeAfterChange = false

        init(
            text: Binding<String>,
            fontSize: Double,
            completionCatalog: SQLCompletionCatalog
        ) {
            _text = text
            self.fontSize = fontSize
            self.completionCatalog = completionCatalog
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            completeAfterChange = replacementString == "."
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let shouldComplete = completeAfterChange
            completeAfterChange = false
            text = textView.string
            highlightSyntax()
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.refresh()
            if shouldComplete {
                DispatchQueue.main.async { [weak textView] in
                    guard let textView, textView.window?.firstResponder === textView else { return }
                    textView.complete(nil)
                }
            }
        }

        func textView(
            _ textView: NSTextView,
            completions _: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let suggestions = SQLCompletionEngine(catalog: completionCatalog).completions(
                in: textView.string,
                cursor: textView.selectedRange().location,
                partialWordRange: charRange
            )
            index?.pointee = suggestions.isEmpty ? -1 : 0
            return suggestions
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

            apply(pattern: SQLVocabulary.keywordPattern, color: SQLColors.keyword, font: .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .semibold), in: textStorage)
            apply(pattern: SQLVocabulary.functionPattern, color: SQLColors.function, in: textStorage)
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

private struct SQLCompletionEngine {
    private struct Candidate {
        let insertion: String
        let match: String
        let rank: Int
    }

    private struct TableReference {
        let schema: String?
        let table: String
        let alias: String?
    }

    private enum LexicalState {
        case code
        case singleQuoted
        case doubleQuoted
        case lineComment
        case blockComment
    }

    let catalog: SQLCompletionCatalog

    func completions(
        in text: String,
        cursor: Int,
        partialWordRange: NSRange
    ) -> [String] {
        let source = text as NSString
        guard cursor >= 0,
              cursor <= source.length,
              partialWordRange.location >= 0,
              NSMaxRange(partialWordRange) <= source.length,
              !Self.isInsideLiteralOrComment(source, cursor: cursor) else { return [] }

        let prefix = source.substring(with: partialWordRange)
        let textBeforePrefix = source.substring(to: partialWordRange.location)

        if let qualifier = Self.qualifier(in: source, before: partialWordRange.location) {
            return filtered(
                qualifiedCandidates(for: qualifier, in: text),
                prefix: prefix
            )
        }

        if Self.isTablePosition(textBeforePrefix) {
            return filtered(
                tableCandidates(rank: 0) + schemaCandidates(rank: 10),
                prefix: prefix
            )
        }

        let references = tableReferences(in: text)
        let referencedTables = resolvedTables(for: references)
        let columnPosition = Self.isColumnPosition(textBeforePrefix)
        var candidates: [Candidate] = []

        if !referencedTables.isEmpty {
            candidates += columnCandidates(from: referencedTables, rank: 0)
        } else if columnPosition {
            candidates += columnCandidates(from: preferredTables, rank: 0)
        }

        candidates += keywordCandidates(rank: columnPosition ? 20 : 0)
        candidates += functionCandidates(rank: columnPosition ? 10 : 5)
        candidates += tableCandidates(rank: 30)
        candidates += schemaCandidates(rank: 40)

        if !prefix.isEmpty {
            candidates += columnCandidates(from: preferredTables, rank: 50)
        }

        return filtered(candidates, prefix: prefix)
    }

    private var orderedSchemas: [DatabaseSchema] {
        catalog.schemas.sorted { lhs, rhs in
            let lhsFocused = matches(lhs.name, catalog.focusedSchema)
            let rhsFocused = matches(rhs.name, catalog.focusedSchema)
            if lhsFocused != rhsFocused { return lhsFocused }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var preferredTables: [DatabaseTable] {
        orderedSchemas.flatMap(\.tables)
    }

    private func qualifiedCandidates(for qualifier: String, in sql: String) -> [Candidate] {
        let references = tableReferences(in: sql)
        if let reference = references.reversed().first(where: { matches($0.alias, qualifier) }),
           let table = resolve(reference) {
            return columnCandidates(from: [table], rank: 0)
        }

        if let schema = orderedSchemas.first(where: { matches($0.name, qualifier) }) {
            return schema.tables.map {
                identifierCandidate($0.name, rank: 0)
            }
        }

        if let table = preferredTables.first(where: { matches($0.name, qualifier) }) {
            return columnCandidates(from: [table], rank: 0)
        }

        return []
    }

    private func keywordCandidates(rank: Int) -> [Candidate] {
        SQLVocabulary.keywords.map {
            Candidate(insertion: $0, match: $0, rank: rank)
        }
    }

    private func functionCandidates(rank: Int) -> [Candidate] {
        SQLVocabulary.functions.map {
            Candidate(insertion: $0, match: $0, rank: rank)
        }
    }

    private func schemaCandidates(rank: Int) -> [Candidate] {
        orderedSchemas.map {
            identifierCandidate($0.name, rank: rank)
        }
    }

    private func tableCandidates(rank: Int) -> [Candidate] {
        var candidates: [Candidate] = []
        for schema in orderedSchemas {
            let focused = matches(schema.name, catalog.focusedSchema)
            for table in schema.tables {
                candidates.append(identifierCandidate(table.name, rank: rank + (focused ? 0 : 5)))
                candidates.append(Candidate(
                    insertion: "\(Self.quotedIdentifier(schema.name)).\(Self.quotedIdentifier(table.name))",
                    match: table.name,
                    rank: rank + (focused ? 5 : 0)
                ))
            }
        }
        return candidates
    }

    private func columnCandidates(from tables: [DatabaseTable], rank: Int) -> [Candidate] {
        tables.flatMap { table in
            table.columns.map {
                identifierCandidate($0.name, rank: rank)
            }
        }
    }

    private func identifierCandidate(_ name: String, rank: Int) -> Candidate {
        Candidate(
            insertion: Self.quotedIdentifier(name),
            match: name,
            rank: rank
        )
    }

    private func tableReferences(in sql: String) -> [TableReference] {
        let pattern = #"\b(?:FROM|JOIN|UPDATE|INTO)\s+((?:"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_$]*)(?:\s*\.\s*(?:"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_$]*))?)(?:\s+(?:AS\s+)?([A-Za-z_][A-Za-z0-9_$]*))?"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let source = sql as NSString
        let matches = expression.matches(
            in: sql,
            range: NSRange(location: 0, length: source.length)
        )

        return matches.compactMap { match -> TableReference? in
            let path = source.substring(with: match.range(at: 1))
                .components(separatedBy: ".")
                .map {
                    Self.unquotedIdentifier(
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .filter { !$0.isEmpty }
            guard let table = path.last, path.count <= 2 else { return nil }

            var alias: String?
            let aliasRange = match.range(at: 2)
            if aliasRange.location != NSNotFound {
                let value = source.substring(with: aliasRange)
                if !SQLVocabulary.keywordSet.contains(value.uppercased()) {
                    alias = value
                }
            }

            return TableReference(
                schema: path.count == 2 ? path[0] : nil,
                table: table,
                alias: alias
            )
        }
    }

    private func resolvedTables(for references: [TableReference]) -> [DatabaseTable] {
        var seen: Set<String> = []
        return references.compactMap(resolve).filter { seen.insert($0.id.lowercased()).inserted }
    }

    private func resolve(_ reference: TableReference) -> DatabaseTable? {
        if let schemaName = reference.schema,
           let schema = orderedSchemas.first(where: { matches($0.name, schemaName) }) {
            return schema.tables.first { matches($0.name, reference.table) }
        }

        if let focusedSchema = catalog.focusedSchema,
           let schema = orderedSchemas.first(where: { matches($0.name, focusedSchema) }),
           let table = schema.tables.first(where: { matches($0.name, reference.table) }) {
            return table
        }

        return preferredTables.first { matches($0.name, reference.table) }
    }

    private func filtered(_ candidates: [Candidate], prefix: String) -> [String] {
        let normalizedPrefix = prefix.lowercased()
        var bestByInsertion: [String: Candidate] = [:]

        for candidate in candidates {
            let normalizedMatch = candidate.match.lowercased()
            guard normalizedPrefix.isEmpty || normalizedMatch.hasPrefix(normalizedPrefix) else { continue }
            let key = candidate.insertion.lowercased()
            if let existing = bestByInsertion[key], existing.rank <= candidate.rank { continue }
            bestByInsertion[key] = candidate
        }

        let sorted = bestByInsertion.values.sorted { lhs, rhs in
            let lhsExact = !normalizedPrefix.isEmpty && lhs.match.lowercased() == normalizedPrefix
            let rhsExact = !normalizedPrefix.isEmpty && rhs.match.lowercased() == normalizedPrefix
            if lhsExact != rhsExact { return lhsExact }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.insertion.localizedCaseInsensitiveCompare(rhs.insertion) == .orderedAscending
        }

        return Array(sorted.prefix(250)).map(\.insertion)
    }

    private func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func qualifier(in source: NSString, before location: Int) -> String? {
        guard location > 0, source.character(at: location - 1) == 46 else { return nil }
        var end = location - 1
        while end > 0, isWhitespace(source.character(at: end - 1)) {
            end -= 1
        }
        guard end > 0 else { return nil }

        if source.character(at: end - 1) == 34 {
            var index = end - 2
            while index >= 0 {
                if source.character(at: index) == 34 {
                    if index > 0, source.character(at: index - 1) == 34 {
                        index -= 2
                        continue
                    }
                    return unquotedIdentifier(
                        source.substring(with: NSRange(location: index, length: end - index))
                    )
                }
                index -= 1
            }
            return nil
        }

        var start = end
        while start > 0, isIdentifierCharacter(source.character(at: start - 1)) {
            start -= 1
        }
        guard start < end else { return nil }
        return source.substring(with: NSRange(location: start, length: end - start))
    }

    private static func isTablePosition(_ text: String) -> Bool {
        guard let word = lastWord(in: text) else { return false }
        return ["FROM", "JOIN", "UPDATE", "INTO", "TABLE"].contains(word)
    }

    private static func isColumnPosition(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(",") || trimmed.hasSuffix("(") { return true }
        guard let word = lastWord(in: trimmed) else { return false }
        return [
            "SELECT", "DISTINCT", "WHERE", "ON", "HAVING", "SET", "BY",
            "AND", "OR", "WHEN", "THEN", "ELSE", "RETURNING"
        ].contains(word)
    }

    private static func lastWord(in text: String) -> String? {
        text.uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .last { !$0.isEmpty }
    }

    private static func quotedIdentifier(_ name: String) -> String {
        let bytes = Array(name.utf8)
        let hasValidStart = bytes.first.map {
            $0 == 95 || (65...90).contains($0) || (97...122).contains($0)
        } ?? false
        let hasValidBody = bytes.dropFirst().allSatisfy {
            $0 == 36 || $0 == 95 || (48...57).contains($0)
                || (65...90).contains($0) || (97...122).contains($0)
        }
        if hasValidStart,
           hasValidBody,
           name == name.lowercased(),
           !SQLVocabulary.keywordSet.contains(name.uppercased()) {
            return name
        }
        return "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func unquotedIdentifier(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\"\"", with: "\"")
    }

    private static func isInsideLiteralOrComment(_ source: NSString, cursor: Int) -> Bool {
        var state = LexicalState.code
        var index = 0

        while index < cursor {
            let character = source.character(at: index)
            let next = index + 1 < cursor ? source.character(at: index + 1) : 0

            switch state {
            case .code:
                if character == 39 {
                    state = .singleQuoted
                } else if character == 34 {
                    state = .doubleQuoted
                } else if character == 45, next == 45 {
                    state = .lineComment
                    index += 1
                } else if character == 47, next == 42 {
                    state = .blockComment
                    index += 1
                }
            case .singleQuoted:
                if character == 39 {
                    if next == 39 {
                        index += 1
                    } else {
                        state = .code
                    }
                }
            case .doubleQuoted:
                if character == 34 {
                    if next == 34 {
                        index += 1
                    } else {
                        state = .code
                    }
                }
            case .lineComment:
                if character == 10 || character == 13 {
                    state = .code
                }
            case .blockComment:
                if character == 42, next == 47 {
                    state = .code
                    index += 1
                }
            }

            index += 1
        }

        return state != .code
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 9 || character == 10 || character == 13 || character == 32
    }

    private static func isIdentifierCharacter(_ character: unichar) -> Bool {
        character == 36 || character == 95
            || (48...57).contains(character)
            || (65...90).contains(character)
            || (97...122).contains(character)
    }
}

final class SQLTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override var rangeForUserCompletion: NSRange {
        let selection = selectedRange()
        guard selection.length == 0 else { return selection }

        let source = string as NSString
        let end = min(selection.location, source.length)
        var start = end
        while start > 0, Self.isCompletionCharacter(source.character(at: start - 1)) {
            start -= 1
        }
        return NSRange(location: start, length: end - start)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 49, modifiers.contains(.control), !modifiers.contains(.command) {
            complete(nil)
            return
        }
        super.keyDown(with: event)
    }

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

    private static func isCompletionCharacter(_ character: unichar) -> Bool {
        character == 36 || character == 95
            || (48...57).contains(character)
            || (65...90).contains(character)
            || (97...122).contains(character)
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
