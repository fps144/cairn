import Foundation
import GRDB
import CairnCore

/// Workspace 实体的 SQLite CRUD。
/// 所有方法 async,内部走 `CairnDatabase.read/write`。
public enum WorkspaceDAO {
    /// Upsert 语义:ON CONFLICT(id) DO UPDATE。
    /// **注意**:`INSERT OR REPLACE` 会在 UNIQUE(cwd) 冲突时删除冲突行 —
    /// 不是我们想要的 upsert 语义。用 ON CONFLICT(id) 只针对 PRIMARY KEY
    /// 冲突做 upsert;UNIQUE(cwd) 冲突(同 cwd 不同 id)抛 SQL 错。
    public static func upsert(_ ws: Workspace, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO workspaces
                    (id, name, cwd, created_at, last_active_at, archived_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        cwd = excluded.cwd,
                        created_at = excluded.created_at,
                        last_active_at = excluded.last_active_at,
                        archived_at = excluded.archived_at
                """,
                arguments: [
                    ws.id.uuidString,
                    ws.name,
                    ws.cwd,
                    ISO8601.string(from: ws.createdAt),
                    ISO8601.string(from: ws.lastActiveAt),
                    ws.archivedAt.map(ISO8601.string(from:)),
                ]
            )
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> Workspace? {
        try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM workspaces WHERE id = ?",
                arguments: [id.uuidString]
            ).map { try Self.make(from: $0) }
        }
    }

    public static func fetchAll(in db: CairnDatabase) async throws -> [Workspace] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM workspaces ORDER BY last_active_at DESC"
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    public static func delete(id: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM workspaces WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Row mapping

    private static func make(from row: Row) throws -> Workspace {
        Workspace(
            id: try row.uuid("id"),
            name: row["name"],
            cwd: row["cwd"],
            createdAt: try row.date("created_at"),
            lastActiveAt: try row.date("last_active_at"),
            archivedAt: try row.dateIfPresent("archived_at")
        )
    }
}
