import Foundation
import GRDB
import CairnCore

public enum SessionDAO {
    public static func upsert(_ s: Session, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO sessions
                    (id, workspace_id, jsonl_path, byte_offset, last_line_number,
                     started_at, ended_at, state, model_used, is_imported)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        workspace_id = excluded.workspace_id,
                        jsonl_path = excluded.jsonl_path,
                        byte_offset = excluded.byte_offset,
                        last_line_number = excluded.last_line_number,
                        started_at = excluded.started_at,
                        ended_at = excluded.ended_at,
                        state = excluded.state,
                        model_used = excluded.model_used,
                        is_imported = excluded.is_imported
                """,
                arguments: [
                    s.id.uuidString,
                    s.workspaceId.uuidString,
                    s.jsonlPath,
                    s.byteOffset,
                    s.lastLineNumber,
                    ISO8601.string(from: s.startedAt),
                    s.endedAt.map(ISO8601.string(from:)),
                    s.state.rawValue,
                    s.modelUsed,
                    s.isImported ? 1 : 0,
                ]
            )
        }
    }

    /// 增量更新 cursor,其他字段不变。JSONLWatcher 每次 ingest 块后调用。
    public static func updateCursor(
        sessionId: UUID,
        byteOffset: Int64,
        lastLineNumber: Int64,
        in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE sessions
                    SET byte_offset = ?, last_line_number = ?
                    WHERE id = ?
                """,
                arguments: [byteOffset, lastLineNumber, sessionId.uuidString]
            )
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> Session? {
        try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM sessions WHERE id = ?",
                arguments: [id.uuidString]
            ).map { try Self.make(from: $0) }
        }
    }

    public static func fetchAll(workspaceId: UUID, in db: CairnDatabase) async throws -> [Session] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM sessions WHERE workspace_id = ? ORDER BY started_at DESC",
                arguments: [workspaceId.uuidString]
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    /// 活跃 session(state IN ('live','idle')),对应 spec §D idx_sessions_state。
    public static func fetchActive(in db: CairnDatabase) async throws -> [Session] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM sessions WHERE state IN ('live', 'idle')"
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    public static func delete(id: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM sessions WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Row mapping

    private static func make(from row: Row) throws -> Session {
        let isImportedInt: Int? = row["is_imported"]
        return Session(
            id: try row.uuid("id"),
            workspaceId: try row.uuid("workspace_id"),
            jsonlPath: row["jsonl_path"],
            startedAt: try row.date("started_at"),
            endedAt: try row.dateIfPresent("ended_at"),
            byteOffset: row["byte_offset"],
            lastLineNumber: row["last_line_number"],
            modelUsed: row["model_used"],
            isImported: (isImportedInt ?? 0) == 1,
            state: try row.rawEnum("state", as: SessionState.self)
        )
    }
}
