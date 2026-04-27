import Foundation
import GRDB

/// 键值对配置存储。value 存 JSON 字符串,调用方自行 decode。
public enum SettingsDAO {
    public static func set(
        key: String, valueJson: String, in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings (key, value_json, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET
                        value_json = excluded.value_json,
                        updated_at = excluded.updated_at
                """,
                arguments: [key, valueJson, ISO8601.string(from: Date())]
            )
        }
    }

    public static func get(
        key: String, in db: CairnDatabase
    ) async throws -> String? {
        try await db.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value_json FROM settings WHERE key = ?",
                arguments: [key]
            )
        }
    }

    public static func delete(key: String, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM settings WHERE key = ?",
                arguments: [key]
            )
        }
    }
}
