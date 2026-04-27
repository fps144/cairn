import Foundation
import GRDB

/// Hook 审批决策(v1.1 起用)。M1.2 提供 CRUD 骨架,
/// v1.1 HookManager 实装时再构造领域类型封装。
public enum ApprovalDAO {
    /// 对应 spec §D approvals 表的完整字段。
    public struct Record: Equatable, Sendable {
        public let id: UUID
        public let sessionId: UUID?
        public let toolName: String
        public let toolInputJson: String
        public let decision: String
        public let decidedBy: String
        public let decidedAt: Date
        public let reason: String?
    }

    public static func upsert(
        id: UUID,
        sessionId: UUID?,
        toolName: String,
        toolInputJson: String,
        decision: String,
        decidedBy: String,
        decidedAt: Date,
        reason: String?,
        in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO approvals
                    (id, session_id, tool_name, tool_input_json,
                     decision, decided_by, decided_at, reason)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        session_id = excluded.session_id,
                        tool_name = excluded.tool_name,
                        tool_input_json = excluded.tool_input_json,
                        decision = excluded.decision,
                        decided_by = excluded.decided_by,
                        decided_at = excluded.decided_at,
                        reason = excluded.reason
                """,
                arguments: [
                    id.uuidString,
                    sessionId?.uuidString,
                    toolName,
                    toolInputJson,
                    decision,
                    decidedBy,
                    ISO8601.string(from: decidedAt),
                    reason,
                ]
            )
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> Record? {
        try await db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM approvals WHERE id = ?",
                arguments: [id.uuidString]
            ) else { return nil }
            return Record(
                id: try row.uuid("id"),
                sessionId: try row.uuidIfPresent("session_id"),
                toolName: row["tool_name"],
                toolInputJson: row["tool_input_json"],
                decision: row["decision"],
                decidedBy: row["decided_by"],
                decidedAt: try row.date("decided_at"),
                reason: row["reason"]
            )
        }
    }
}
