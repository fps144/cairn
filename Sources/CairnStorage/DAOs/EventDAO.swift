import Foundation
import GRDB
import CairnCore

public enum EventDAO {
    public enum DAOError: Error {
        case noRowReturned(String)
        case invalidUUID(String)
    }

    public static func upsert(_ event: Event, in db: CairnDatabase) async throws {
        try await db.write { db in
            try Self.upsertSync(event, db: db)
        }
    }

    /// 批量 upsert,单事务。JSONL ingest 每 chunk 调用。
    /// spec §7.8:单事务 ≤ 500 条,调用方按需切分。
    public static func upsertBatch(
        _ events: [Event],
        in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            for e in events {
                try Self.upsertSync(e, db: db)
            }
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> Event? {
        try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM events WHERE id = ?",
                arguments: [id.uuidString]
            ).map { try Self.make(from: $0) }
        }
    }

    /// 按 session 分页取 event,排序 (line_number ASC, block_index ASC)。
    public static func fetch(
        sessionId: UUID, limit: Int, offset: Int,
        in db: CairnDatabase
    ) async throws -> [Event] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM events
                    WHERE session_id = ?
                    ORDER BY line_number ASC, block_index ASC
                    LIMIT ? OFFSET ?
                """,
                arguments: [sessionId.uuidString, limit, offset]
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    /// 按 toolUseId 查(spec §4.4 配对用)。
    public static func fetchByToolUseId(
        _ toolUseId: String, in db: CairnDatabase
    ) async throws -> [Event] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM events
                    WHERE tool_use_id = ?
                    ORDER BY line_number ASC, block_index ASC
                """,
                arguments: [toolUseId]
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    public static func fetchByType(
        _ type: EventType, sessionId: UUID,
        in db: CairnDatabase
    ) async throws -> [Event] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM events
                    WHERE session_id = ? AND type = ?
                    ORDER BY line_number ASC, block_index ASC
                """,
                arguments: [sessionId.uuidString, type.rawValue]
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    public static func delete(id: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM events WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    /// 按 `(session_id, line_number, block_index)` 复合键 upsert,返回 DB stable id。
    ///
    /// M2.3 EventIngestor 用:parser 生成的 Event.id 是随机 UUID,每次 parse
    /// 不同;但 events 表里同一个 (sid, line, block) 必须有稳定 id 供
    /// `paired_event_id` 指向。SQLite UPSERT + RETURNING 一步完成。
    ///
    /// - 已存在 row:用 excluded 字段覆盖**非 id** 字段,id 保持旧值
    /// - 不存在:插入 Event.id 作为新 stable id
    ///
    /// 返回值:DB 里这行的 id(caller 用 `Event.withId(_:)` 覆盖)。
    /// **依赖 schema v2 的 `UNIQUE INDEX idx_events_session_seq`**。
    public static func upsertByLineBlockSync(
        _ e: Event, db: GRDB.Database
    ) throws -> UUID {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                INSERT INTO events
                (id, session_id, type, category, tool_name, tool_use_id,
                 paired_event_id, timestamp, line_number, block_index,
                 summary, raw_payload_json, byte_offset_in_jsonl)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_id, line_number, block_index) DO UPDATE SET
                    type = excluded.type,
                    category = excluded.category,
                    tool_name = excluded.tool_name,
                    tool_use_id = excluded.tool_use_id,
                    paired_event_id = excluded.paired_event_id,
                    timestamp = excluded.timestamp,
                    summary = excluded.summary,
                    raw_payload_json = excluded.raw_payload_json,
                    byte_offset_in_jsonl = excluded.byte_offset_in_jsonl
                RETURNING id
                """,
            arguments: [
                e.id.uuidString,
                e.sessionId.uuidString,
                e.type.rawValue,
                e.category?.rawValue,
                e.toolName,
                e.toolUseId,
                e.pairedEventId?.uuidString,
                ISO8601.string(from: e.timestamp),
                e.lineNumber,
                e.blockIndex,
                e.summary,
                e.rawPayloadJson,
                e.byteOffsetInJsonl,
            ]
        ) else {
            throw DAOError.noRowReturned("upsertByLineBlock")
        }
        let idStr: String = row["id"]
        guard let uuid = UUID(uuidString: idStr) else {
            throw DAOError.invalidUUID(idStr)
        }
        return uuid
    }

    // MARK: - helpers

    private static func upsertSync(_ e: Event, db: GRDB.Database) throws {
        try db.execute(
            sql: """
                INSERT INTO events
                (id, session_id, type, category, tool_name, tool_use_id,
                 paired_event_id, timestamp, line_number, block_index,
                 summary, raw_payload_json, byte_offset_in_jsonl)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    session_id = excluded.session_id,
                    type = excluded.type,
                    category = excluded.category,
                    tool_name = excluded.tool_name,
                    tool_use_id = excluded.tool_use_id,
                    paired_event_id = excluded.paired_event_id,
                    timestamp = excluded.timestamp,
                    line_number = excluded.line_number,
                    block_index = excluded.block_index,
                    summary = excluded.summary,
                    raw_payload_json = excluded.raw_payload_json,
                    byte_offset_in_jsonl = excluded.byte_offset_in_jsonl
            """,
            arguments: [
                e.id.uuidString,
                e.sessionId.uuidString,
                e.type.rawValue,
                e.category?.rawValue,
                e.toolName,
                e.toolUseId,
                e.pairedEventId?.uuidString,
                ISO8601.string(from: e.timestamp),
                e.lineNumber,
                e.blockIndex,
                e.summary,
                e.rawPayloadJson,
                e.byteOffsetInJsonl,
            ]
        )
    }

    private static func make(from row: Row) throws -> Event {
        let categoryStr: String? = row["category"]
        return Event(
            id: try row.uuid("id"),
            sessionId: try row.uuid("session_id"),
            type: try row.rawEnum("type", as: EventType.self),
            category: categoryStr.map { ToolCategory(rawValue: $0) },
            toolName: row["tool_name"],
            toolUseId: row["tool_use_id"],
            pairedEventId: try row.uuidIfPresent("paired_event_id"),
            timestamp: try row.date("timestamp"),
            lineNumber: row["line_number"],
            blockIndex: row["block_index"],
            summary: row["summary"],
            rawPayloadJson: row["raw_payload_json"],
            byteOffsetInJsonl: row["byte_offset_in_jsonl"]
        )
    }
}
