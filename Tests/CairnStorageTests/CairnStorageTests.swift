import XCTest
import GRDB
@testable import CairnStorage

final class CairnStorageTests: XCTestCase {
    func test_scaffoldVersion_matchesCore() {
        // CairnStorage.scaffoldVersion 与 CairnCore.scaffoldVersion 相等
        XCTAssertEqual(CairnStorage.scaffoldVersion,
                       "0.10.0-m2.5",
                       "M2.5 bump 到 0.10.0-m2.5")
    }

    func test_inMemoryDatabase_opensAndClosesCleanly() async throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("noop") { db in
            try db.execute(sql: "CREATE TABLE test (id INTEGER)")
        }
        let db = try await CairnDatabase(location: .inMemory, migrator: migrator)
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM test") ?? -1
        }
        XCTAssertEqual(count, 0)
    }
}
