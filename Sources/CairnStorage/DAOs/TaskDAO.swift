import Foundation
import GRDB
import CairnCore

public enum TaskDAO {
    /// Upsert tasks 行 + 同步 task_sessions 关联(delete-then-insert 模式)。
    public static func upsert(_ task: CairnTask, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tasks
                    (id, workspace_id, title, intent, status,
                     created_at, updated_at, completed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        workspace_id = excluded.workspace_id,
                        title = excluded.title,
                        intent = excluded.intent,
                        status = excluded.status,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at,
                        completed_at = excluded.completed_at
                """,
                arguments: [
                    task.id.uuidString,
                    task.workspaceId.uuidString,
                    task.title,
                    task.intent,
                    task.status.rawValue,
                    ISO8601.string(from: task.createdAt),
                    ISO8601.string(from: task.updatedAt),
                    task.completedAt.map(ISO8601.string(from:)),
                ]
            )
            // 清理旧关联
            try db.execute(
                sql: "DELETE FROM task_sessions WHERE task_id = ?",
                arguments: [task.id.uuidString]
            )
            // 按当前 sessionIds 重建
            let now = ISO8601.string(from: Date())
            for sid in task.sessionIds {
                try db.execute(
                    sql: """
                        INSERT INTO task_sessions (task_id, session_id, attached_at)
                        VALUES (?, ?, ?)
                    """,
                    arguments: [task.id.uuidString, sid.uuidString, now]
                )
            }
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> CairnTask? {
        try await db.read { db in
            try Self.fetchSync(id: id, db: db)
        }
    }

    public static func fetchAll(
        workspaceId: UUID,
        status: TaskStatus? = nil,
        in db: CairnDatabase
    ) async throws -> [CairnTask] {
        try await db.read { db in
            var sql = "SELECT id FROM tasks WHERE workspace_id = ?"
            var args: [DatabaseValueConvertible] = [workspaceId.uuidString]
            if let status {
                sql += " AND status = ?"
                args.append(status.rawValue)
            }
            sql += " ORDER BY updated_at DESC"
            let ids = try UUID.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return try ids.compactMap { id -> CairnTask? in
                try Self.fetchSync(id: id, db: db)
            }
        }
    }

    public static func delete(id: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            // task_sessions 通过 ON DELETE CASCADE 自动删除,这里只删 tasks 行
            try db.execute(
                sql: "DELETE FROM tasks WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - 同步 helper(复用,避免 fetchAll 里重复 await)

    private static func fetchSync(id: UUID, db: GRDB.Database) throws -> CairnTask? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM tasks WHERE id = ?",
            arguments: [id.uuidString]
        ) else { return nil }

        // ORDER BY session_id 让 roundtrip 结果确定(字典序);
        // task_sessions 的语义是"集合",顺序不承载业务含义。
        let sessionIds = try UUID.fetchAll(
            db,
            sql: "SELECT session_id FROM task_sessions WHERE task_id = ? ORDER BY session_id",
            arguments: [id.uuidString]
        )

        return try CairnTask(
            id: try row.uuid("id"),
            workspaceId: try row.uuid("workspace_id"),
            title: row["title"],
            intent: row["intent"],
            status: try row.rawEnum("status", as: TaskStatus.self),
            sessionIds: sessionIds,
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            completedAt: try row.dateIfPresent("completed_at")
        )
    }
}
