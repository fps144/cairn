import Foundation
import GRDB

/// 窗口/标签布局。存储为 JSON blob(layout schema 由 CairnUI 定义,M1.3 起用)。
public enum LayoutStateDAO {
    private static let upsertSQL = """
        INSERT INTO layout_states
        (workspace_id, layout_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(workspace_id) DO UPDATE SET
            layout_json = excluded.layout_json,
            updated_at = excluded.updated_at
        """

    public static func upsert(
        workspaceId: UUID,
        layoutJson: String,
        updatedAt: Date,
        in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: upsertSQL,
                arguments: [
                    workspaceId.uuidString,
                    layoutJson,
                    ISO8601.string(from: updatedAt),
                ]
            )
        }
    }

    /// 同步 upsert。给 app 终止路径 / 必须立即落盘的 onChange 调用用。
    public static func upsertSync(
        workspaceId: UUID,
        layoutJson: String,
        updatedAt: Date,
        in db: CairnDatabase
    ) throws {
        try db.writeSync { db in
            try db.execute(
                sql: upsertSQL,
                arguments: [
                    workspaceId.uuidString,
                    layoutJson,
                    ISO8601.string(from: updatedAt),
                ]
            )
        }
    }

    public static func fetch(
        workspaceId: UUID, in db: CairnDatabase
    ) async throws -> (layoutJson: String, updatedAt: Date)? {
        try await db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM layout_states WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            ) else { return nil }
            let json: String = row["layout_json"]
            let updated: Date = try row.date("updated_at")
            return (json, updated)
        }
    }
}
