import XCTest
@testable import Selektos

final class D1ServiceTests: XCTestCase {
    func testSchemaMetadataCommandUsesEscapedLiteralTableNames() {
        XCTAssertEqual(
            D1Service().schemaMetadataCommand(for: ["users", "audit'log"]),
            """
            PRAGMA table_info('users');
            PRAGMA table_info('audit''log');
            """
        )
    }

    func testDecodesBatchedTableInfoResponses() throws {
        let data = try XCTUnwrap(
            """
            [
              {
                "results": [
                  {"cid": 1, "name": "email", "type": "TEXT", "notnull": 1, "pk": 0},
                  {"cid": 0, "name": "id", "type": "TEXT", "notnull": 0, "pk": 1}
                ],
                "success": true
              },
              {
                "results": [
                  {"cid": 0, "name": "total", "type": "INTEGER", "notnull": 1, "pk": 0}
                ],
                "success": true
              }
            ]
            """.data(using: .utf8)
        )

        let schemas = try D1Service().decodeSchema(
            tableNames: ["users", "invoices"],
            from: data
        )

        XCTAssertEqual(schemas.count, 1)
        XCTAssertEqual(schemas[0].name, "main")
        XCTAssertEqual(schemas[0].tables.map(\.name), ["users", "invoices"])
        XCTAssertEqual(schemas[0].tables[0].columns.map(\.name), ["id", "email"])
        XCTAssertTrue(schemas[0].tables[0].columns[0].isPrimaryKey)
        XCTAssertTrue(schemas[0].tables[0].columns[0].isNullable)
        XCTAssertFalse(schemas[0].tables[0].columns[1].isNullable)
        XCTAssertEqual(schemas[0].tables[1].columns[0].dataType, "INTEGER")
    }
}
