import Foundation
import GRDB
import CairnCore

public enum PlanDAO {
    public static func upsert(_ plan: Plan, in db: CairnDatabase) async throws {
        let stepsJson = String(
            data: try CairnCore.jsonEncoder.encode(plan.steps),
            encoding: .utf8
        ) ?? "[]"
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO plans
                    (id, task_id, source, steps_json, markdown_raw, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        task_id = excluded.task_id,
                        source = excluded.source,
                        steps_json = excluded.steps_json,
                        markdown_raw = excluded.markdown_raw,
                        updated_at = excluded.updated_at
                """,
                arguments: [
                    plan.id.uuidString,
                    plan.taskId.uuidString,
                    plan.source.rawValue,
                    stepsJson,
                    plan.markdownRaw,
                    ISO8601.string(from: plan.updatedAt),
                ]
            )
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> Plan? {
        try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM plans WHERE id = ?",
                arguments: [id.uuidString]
            ).map { try Self.make(from: $0) }
        }
    }

    /// 按 task 查,按 updated_at DESC(spec §D idx_plans_task 索引)。
    public static func fetchByTask(taskId: UUID, in db: CairnDatabase) async throws -> [Plan] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM plans WHERE task_id = ? ORDER BY updated_at DESC",
                arguments: [taskId.uuidString]
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    public static func delete(id: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM plans WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    private static func make(from row: Row) throws -> Plan {
        let stepsJson: String = row["steps_json"]
        let steps: [PlanStep] = try CairnCore.jsonDecoder.decode(
            [PlanStep].self,
            from: Data(stepsJson.utf8)
        )
        return Plan(
            id: try row.uuid("id"),
            taskId: try row.uuid("task_id"),
            source: try row.rawEnum("source", as: PlanSource.self),
            steps: steps,
            markdownRaw: row["markdown_raw"],
            updatedAt: try row.date("updated_at")
        )
    }
}
