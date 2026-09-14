import Foundation

enum SQLDialect: Equatable, Sendable {
    case postgresql
    case sqlite
}

enum ReadOnlySQLValidator {
    static func validate(_ sql: String, dialect: SQLDialect) throws {
        let statements = try SQLTokenizer.tokenize(sql, dialect: dialect).splitIntoStatements()
        guard !statements.isEmpty else {
            throw ReadOnlySQLError.emptyQuery
        }
        guard statements.count == 1 else {
            throw ReadOnlySQLError.multipleStatements
        }

        for statement in statements {
            let words = statement.compactMap(\.unquotedWord)
            guard let first = words.first else {
                throw ReadOnlySQLError.unsupportedStatement("unknown")
            }
            guard allowedFirstKeywords.contains(first) else {
                throw ReadOnlySQLError.unsupportedStatement(first)
            }

            if let blocked = words.first(where: blockedKeywords.contains) {
                throw ReadOnlySQLError.blockedKeyword(blocked)
            }
            if let blockedFunction = blockedFunction(in: statement) {
                throw ReadOnlySQLError.blockedFunction(blockedFunction)
            }

            if first == "PRAGMA" {
                try validatePragma(statement, dialect: dialect)
            }
        }
    }

    private static let allowedFirstKeywords: Set<String> = [
        "EXPLAIN", "PRAGMA", "SELECT", "SHOW", "TABLE", "VALUES", "WITH"
    ]

    private static let blockedKeywords: Set<String> = [
        "DELETE", "EXECUTE", "INSERT", "INTO", "MERGE", "REPLACE", "UPDATE"
    ]

    private static let blockedFunctions: Set<String> = [
        "DBLINK_EXEC", "LOAD_EXTENSION", "LO_CREATE", "LO_EXPORT", "LO_IMPORT",
        "LO_UNLINK", "NEXTVAL", "PG_ADVISORY_LOCK", "PG_ADVISORY_UNLOCK",
        "PG_ADVISORY_UNLOCK_ALL", "PG_ADVISORY_XACT_LOCK", "PG_BACKUP_START",
        "PG_BACKUP_STOP", "PG_CANCEL_BACKEND", "PG_COPY_LOGICAL_REPLICATION_SLOT",
        "PG_COPY_PHYSICAL_REPLICATION_SLOT", "PG_CREATE_LOGICAL_REPLICATION_SLOT",
        "PG_CREATE_PHYSICAL_REPLICATION_SLOT", "PG_CREATE_RESTORE_POINT",
        "PG_DROP_REPLICATION_SLOT", "PG_EXPORT_SNAPSHOT",
        "PG_LOG_BACKEND_MEMORY_CONTEXTS", "PG_LOGICAL_EMIT_MESSAGE", "PG_NOTIFY",
        "PG_PROMOTE", "PG_RELOAD_CONF", "PG_REPLICATION_ORIGIN_ADVANCE",
        "PG_REPLICATION_ORIGIN_SESSION_RESET", "PG_REPLICATION_ORIGIN_SESSION_SETUP",
        "PG_REPLICATION_ORIGIN_XACT_RESET", "PG_REPLICATION_ORIGIN_XACT_SETUP",
        "PG_REPLICATION_SLOT_ADVANCE", "PG_ROTATE_LOGFILE", "PG_START_BACKUP",
        "PG_STAT_FORCE_NEXT_FLUSH", "PG_STAT_RESET", "PG_STAT_RESET_SHARED",
        "PG_STAT_RESET_SINGLE_FUNCTION_COUNTERS", "PG_STAT_RESET_SINGLE_TABLE_COUNTERS",
        "PG_STOP_BACKUP", "PG_SWITCH_WAL", "PG_TERMINATE_BACKEND",
        "PG_TRY_ADVISORY_LOCK", "PG_TRY_ADVISORY_XACT_LOCK", "PG_WAL_REPLAY_PAUSE",
        "PG_WAL_REPLAY_RESUME", "SET_CONFIG", "SETVAL", "WRITEFILE"
    ]

    private static let blockedFunctionPrefixes = [
        "DBLINK", "PG_FILE_"
    ]

    private static let readOnlyPragmas: Set<String> = [
        "COLLATION_LIST", "COMPILE_OPTIONS", "DATABASE_LIST", "FOREIGN_KEY_LIST",
        "FUNCTION_LIST", "INDEX_INFO", "INDEX_LIST", "INDEX_XINFO", "MODULE_LIST",
        "PRAGMA_LIST", "TABLE_INFO", "TABLE_LIST", "TABLE_XINFO"
    ]

    private static func validatePragma(_ tokens: [SQLToken], dialect: SQLDialect) throws {
        guard dialect == .sqlite else {
            throw ReadOnlySQLError.unsupportedStatement("PRAGMA")
        }
        guard !tokens.contains(where: { $0.symbol == "=" }) else {
            throw ReadOnlySQLError.blockedPragma
        }

        var index = 1
        guard index < tokens.count, let firstName = tokens[index].unquotedWord else {
            throw ReadOnlySQLError.blockedPragma
        }
        index += 1

        let pragmaName: String
        if index + 1 < tokens.count,
           tokens[index].symbol == ".",
           let qualifiedName = tokens[index + 1].unquotedWord {
            pragmaName = qualifiedName
        } else {
            pragmaName = firstName
        }

        guard readOnlyPragmas.contains(pragmaName) else {
            throw ReadOnlySQLError.blockedPragma
        }
    }

    private static func blockedFunction(in tokens: [SQLToken]) -> String? {
        for index in tokens.indices {
            guard let name = tokens[index].word,
                  index + 1 < tokens.count,
                  tokens[index + 1].symbol == "(" else {
                continue
            }
            if blockedFunctions.contains(name)
                || blockedFunctionPrefixes.contains(where: name.hasPrefix) {
                return name
            }
        }
        return nil
    }
}

enum ReadOnlySQLError: LocalizedError, Equatable {
    case emptyQuery
    case malformedSQL(String)
    case multipleStatements
    case unsupportedStatement(String)
    case blockedKeyword(String)
    case blockedFunction(String)
    case blockedPragma

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "Enter a SQL query."
        case .malformedSQL(let detail):
            "The SQL could not be validated for read-only access: \(detail)."
        case .multipleStatements:
            "Read-only MCP access permits one SQL statement per tool call."
        case .unsupportedStatement(let keyword):
            "Read-only MCP access only permits SELECT-style queries; \(keyword) is not allowed."
        case .blockedKeyword(let keyword):
            "Read-only MCP access blocked SQL containing \(keyword)."
        case .blockedFunction(let function):
            "Read-only MCP access blocked the side-effecting function \(function)."
        case .blockedPragma:
            "Read-only MCP access only permits SQLite metadata PRAGMAs."
        }
    }
}

private struct SQLToken: Equatable {
    enum Kind: Equatable {
        case word(String, quoted: Bool)
        case symbol(String)
    }

    let kind: Kind

    var word: String? {
        guard case .word(let value, _) = kind else { return nil }
        return value
    }

    var unquotedWord: String? {
        guard case .word(let value, quoted: false) = kind else { return nil }
        return value
    }

    var symbol: String? {
        guard case .symbol(let value) = kind else { return nil }
        return value
    }
}

private extension Array where Element == SQLToken {
    func splitIntoStatements() -> [[SQLToken]] {
        var statements: [[SQLToken]] = []
        var current: [SQLToken] = []

        for token in self {
            if token.symbol == ";" {
                if !current.isEmpty {
                    statements.append(current)
                    current = []
                }
            } else {
                current.append(token)
            }
        }
        if !current.isEmpty {
            statements.append(current)
        }
        return statements
    }
}

private enum SQLTokenizer {
    static func tokenize(_ sql: String, dialect: SQLDialect) throws -> [SQLToken] {
        let scalars = Array(sql.unicodeScalars)
        var tokens: [SQLToken] = []
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                index += 1
            } else if matches("--", scalars, at: index) {
                index += 2
                while index < scalars.count, scalars[index] != "\n" {
                    index += 1
                }
            } else if matches("/*", scalars, at: index) {
                index = try skipBlockComment(scalars, from: index)
            } else if scalar == "'" {
                index = try skipQuotedValue(scalars, from: index, delimiter: "'")
            } else if scalar == "\"" {
                let identifier = try readQuotedIdentifier(
                    scalars,
                    from: index,
                    openingDelimiter: "\"",
                    closingDelimiter: "\""
                )
                tokens.append(SQLToken(kind: .word(identifier.value.uppercased(), quoted: true)))
                index = identifier.nextIndex
            } else if dialect == .sqlite, scalar == "`" {
                let identifier = try readQuotedIdentifier(
                    scalars,
                    from: index,
                    openingDelimiter: "`",
                    closingDelimiter: "`"
                )
                tokens.append(SQLToken(kind: .word(identifier.value.uppercased(), quoted: true)))
                index = identifier.nextIndex
            } else if dialect == .sqlite, scalar == "[" {
                let identifier = try readQuotedIdentifier(
                    scalars,
                    from: index,
                    openingDelimiter: "[",
                    closingDelimiter: "]",
                    supportsDoubledClosingDelimiter: false
                )
                tokens.append(SQLToken(kind: .word(identifier.value.uppercased(), quoted: true)))
                index = identifier.nextIndex
            } else if dialect == .postgresql,
                      scalar == "$",
                      let delimiter = dollarDelimiter(scalars, at: index) {
                index = try skipDollarQuotedValue(
                    scalars,
                    from: delimiter.contentStart,
                    delimiter: delimiter.value
                )
            } else if isIdentifierStart(scalar) {
                let start = index
                index += 1
                while index < scalars.count, isIdentifierContinuation(scalars[index]) {
                    index += 1
                }
                let value = String(String.UnicodeScalarView(scalars[start..<index])).uppercased()
                tokens.append(SQLToken(kind: .word(value, quoted: false)))
            } else {
                tokens.append(SQLToken(kind: .symbol(String(scalar))))
                index += 1
            }
        }

        return tokens
    }

    private static func skipBlockComment(
        _ scalars: [UnicodeScalar],
        from start: Int
    ) throws -> Int {
        var index = start + 2
        while index < scalars.count {
            if matches("*/", scalars, at: index) {
                return index + 2
            } else {
                index += 1
            }
        }
        throw ReadOnlySQLError.malformedSQL("unterminated block comment")
    }

    private static func skipQuotedValue(
        _ scalars: [UnicodeScalar],
        from start: Int,
        delimiter: UnicodeScalar
    ) throws -> Int {
        var index = start + 1
        while index < scalars.count {
            guard scalars[index] == delimiter else {
                index += 1
                continue
            }
            if index + 1 < scalars.count, scalars[index + 1] == delimiter {
                index += 2
            } else {
                return index + 1
            }
        }
        throw ReadOnlySQLError.malformedSQL("unterminated quoted value")
    }

    private static func readQuotedIdentifier(
        _ scalars: [UnicodeScalar],
        from start: Int,
        openingDelimiter: UnicodeScalar,
        closingDelimiter: UnicodeScalar,
        supportsDoubledClosingDelimiter: Bool = true
    ) throws -> (value: String, nextIndex: Int) {
        precondition(scalars[start] == openingDelimiter)
        var value: [UnicodeScalar] = []
        var index = start + 1
        while index < scalars.count {
            guard scalars[index] == closingDelimiter else {
                value.append(scalars[index])
                index += 1
                continue
            }
            if supportsDoubledClosingDelimiter,
               index + 1 < scalars.count,
               scalars[index + 1] == closingDelimiter {
                value.append(closingDelimiter)
                index += 2
            } else {
                return (String(String.UnicodeScalarView(value)), index + 1)
            }
        }
        throw ReadOnlySQLError.malformedSQL("unterminated quoted identifier")
    }

    private static func dollarDelimiter(
        _ scalars: [UnicodeScalar],
        at start: Int
    ) -> (value: [UnicodeScalar], contentStart: Int)? {
        var index = start + 1
        if index < scalars.count, scalars[index] == "$" {
            return (Array(scalars[start...index]), index + 1)
        }
        guard index < scalars.count, isIdentifierStart(scalars[index]) else {
            return nil
        }
        index += 1
        while index < scalars.count, isDollarTagContinuation(scalars[index]) {
            index += 1
        }
        guard index < scalars.count, scalars[index] == "$" else {
            return nil
        }
        return (Array(scalars[start...index]), index + 1)
    }

    private static func skipDollarQuotedValue(
        _ scalars: [UnicodeScalar],
        from start: Int,
        delimiter: [UnicodeScalar]
    ) throws -> Int {
        var index = start
        while index + delimiter.count <= scalars.count {
            if Array(scalars[index..<(index + delimiter.count)]) == delimiter {
                return index + delimiter.count
            }
            index += 1
        }
        throw ReadOnlySQLError.malformedSQL("unterminated dollar-quoted value")
    }

    private static func matches(
        _ value: String,
        _ scalars: [UnicodeScalar],
        at index: Int
    ) -> Bool {
        let expected = Array(value.unicodeScalars)
        guard index + expected.count <= scalars.count else { return false }
        return Array(scalars[index..<(index + expected.count)]) == expected
    }

    private static func isIdentifierStart(_ scalar: UnicodeScalar) -> Bool {
        scalar == "_" || (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
    }

    private static func isIdentifierContinuation(_ scalar: UnicodeScalar) -> Bool {
        isIdentifierStart(scalar) || scalar == "$" || (scalar.value >= 48 && scalar.value <= 57)
    }

    private static func isDollarTagContinuation(_ scalar: UnicodeScalar) -> Bool {
        isIdentifierStart(scalar) || (scalar.value >= 48 && scalar.value <= 57)
    }
}
