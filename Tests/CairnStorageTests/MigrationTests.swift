import XCTest
import GRDB
@testable import CairnStorage

final class MigrationTests: XCTestCase {
    func test_v1Migration_createsAll11Tables() async throws {
        let db = try await makeInMemoryDatabase()
        let tables = try await db.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type='table' AND name NOT LIKE 'sqlite_%'
                  AND name NOT LIKE 'grdb_%'
                ORDER BY name
                """)
        }
        let expected = [
            "approvals",
            "budgets",
            "events",
            "layout_states",
            "plans",
            "schema_versions",
            "sessions",
            "settings",
            "task_sessions",
            "tasks",
            "workspaces",
        ]
        XCTAssertEqual(tables, expected,
                       "v1 迁移应创建 spec §D 的全部 11 张表")
    }

    func test_v1Migration_insertsSchemaVersionsRow() async throws {
        let db = try await makeInMemoryDatabase()
        let version = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT version FROM schema_versions WHERE version = 1")
        }
        XCTAssertEqual(version, 1, "schema_versions 应含 v1 行")
    }

    func test_v1Migration_foreignKeysEnabled() async throws {
        let db = try await makeInMemoryDatabase()
        let fkEnabled = try await db.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
        }
        XCTAssertEqual(fkEnabled, 1, "foreign_keys PRAGMA 应启用(spec §7.8)")
    }

    func test_v1Migration_isIdempotent() async throws {
        // 重复 open 同一内存 DB 不合理(每次 new instance),
        // 但我们可以跑相同 migrator 两次,确认 GRDB 幂等。
        // GRDB DatabaseMigrator 内置幂等性(通过 grdb_migrations 表记录)。
        let migrator = CairnStorage.makeMigrator()
        let queue = try DatabaseQueue(path: ":memory:")
        try migrator.migrate(queue)
        try migrator.migrate(queue)  // 第二次不应 throw
        let count = try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_versions") ?? 0
        }
        XCTAssertEqual(count, 1, "重复 migrate 不应重复插入 schema_versions")
    }

    // MARK: - Helper
    private func makeInMemoryDatabase() async throws -> CairnDatabase {
        try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
    }
}
