import Foundation
import XCTest
@testable import Selektos

final class SchemaFocusTests: XCTestCase {
    func testNoFocusLeavesServerDefault() {
        XCTAssertNil(PostgresService.searchPathValue(for: nil))
        XCTAssertNil(PostgresService.searchPathValue(for: ""))
        XCTAssertNil(PostgresService.searchPathValue(for: "   "))
    }

    func testFocusedSchemaComesBeforePublic() {
        XCTAssertEqual(PostgresService.searchPathValue(for: "app"), "\"app\", \"public\"")
        XCTAssertEqual(PostgresService.searchPathValue(for: " app "), "\"app\", \"public\"")
    }

    func testPublicIsNotDuplicated() {
        XCTAssertEqual(PostgresService.searchPathValue(for: "public"), "\"public\"")
    }

    func testIdentifierQuotingIsEscaped() {
        XCTAssertEqual(PostgresService.searchPathValue(for: "we\"ird"), "\"we\"\"ird\", \"public\"")
        XCTAssertEqual(PostgresService.searchPathValue(for: "Mixed Case"), "\"Mixed Case\", \"public\"")
    }

    func testInternalSchemasAreHiddenFromFocusPicker() {
        XCTAssertTrue(AppStore.isInternalSchema("pg_catalog"))
        XCTAssertTrue(AppStore.isInternalSchema("pg_toast"))
        XCTAssertTrue(AppStore.isInternalSchema("information_schema"))
        XCTAssertFalse(AppStore.isInternalSchema("public"))
        XCTAssertFalse(AppStore.isInternalSchema("app"))
    }

    func testQueryTabDecodesWithoutStoredSchema() throws {
        let legacy = Data(#"{"id":"6C4E1E3A-0F1E-4E5B-9A1B-1C2D3E4F5A6B","title":"T","sql":"SELECT 1;"}"#.utf8)
        let tab = try JSONDecoder().decode(QueryTab.self, from: legacy)
        XCTAssertNil(tab.schema)
        XCTAssertEqual(tab.sql, "SELECT 1;")
    }

    func testQueryTabRoundTripsSchema() throws {
        var tab = QueryTab()
        tab.schema = "app"
        let decoded = try JSONDecoder().decode(QueryTab.self, from: JSONEncoder().encode(tab))
        XCTAssertEqual(decoded.schema, "app")
    }
}
