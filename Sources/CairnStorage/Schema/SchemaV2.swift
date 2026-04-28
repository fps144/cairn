import Foundation

/// Schema v2:events 表加 UNIQUE INDEX(session_id, line_number, block_index)。
///
/// 原因(M2.3):JSONLParser 是纯函数,每次 parse 同一行生成新 UUID。
/// M2.3 EventIngestor 需要按 (sid, line, block) 复合键 upsert 拿回
/// DB stable id,以便 tool_use↔result 配对的 paired_event_id 指向正确
/// 的 row id。v1 只有普通 INDEX 没 UNIQUE 约束,ON CONFLICT 无法按复合键触发。
///
/// SQLite 不支持 ALTER TABLE 加 UNIQUE 约束,但 UNIQUE INDEX 效果等同
/// —— ON CONFLICT 和 RETURNING 都认。免重建表。
enum SchemaV2 {
    static let statements: [String] = [
        // 先 drop 原普通索引(同名);再建 UNIQUE 索引
        "DROP INDEX IF EXISTS idx_events_session_seq",
        """
        CREATE UNIQUE INDEX idx_events_session_seq
        ON events(session_id, line_number, block_index)
        """,
    ]
}
