import Foundation
import GRDB

extension CairnStorage {
    /// 构造 Cairn 主数据库的 migrator。包含 v1 schema。
    public static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            for sql in SchemaV1.statements {
                try db.execute(sql: sql)
            }
            // 写入 schema_versions 行
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            try db.execute(
                sql: """
                    INSERT INTO schema_versions (version, applied_at, description)
                    VALUES (?, ?, ?)
                """,
                arguments: [1, formatter.string(from: Date()),
                            "v1.0 initial schema (11 tables)"]
            )
        }

        return migrator
    }
}
