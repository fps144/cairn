import Foundation
import GRDB
import CairnCore

public enum BudgetDAO {
    public static func upsert(_ b: Budget, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO budgets
                    (task_id,
                     max_input_tokens, max_output_tokens, max_cost_usd, max_wall_seconds,
                     used_input_tokens, used_output_tokens, used_cost_usd, used_wall_seconds,
                     state, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(task_id) DO UPDATE SET
                        max_input_tokens = excluded.max_input_tokens,
                        max_output_tokens = excluded.max_output_tokens,
                        max_cost_usd = excluded.max_cost_usd,
                        max_wall_seconds = excluded.max_wall_seconds,
                        used_input_tokens = excluded.used_input_tokens,
                        used_output_tokens = excluded.used_output_tokens,
                        used_cost_usd = excluded.used_cost_usd,
                        used_wall_seconds = excluded.used_wall_seconds,
                        state = excluded.state,
                        updated_at = excluded.updated_at
                """,
                arguments: [
                    b.taskId.uuidString,
                    b.maxInputTokens,
                    b.maxOutputTokens,
                    b.maxCostUSD,
                    b.maxWallSeconds,
                    b.usedInputTokens,
                    b.usedOutputTokens,
                    b.usedCostUSD,
                    b.usedWallSeconds,
                    b.state.rawValue,
                    ISO8601.string(from: b.updatedAt),
                ]
            )
        }
    }

    public static func fetch(taskId: UUID, in db: CairnDatabase) async throws -> Budget? {
        try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM budgets WHERE task_id = ?",
                arguments: [taskId.uuidString]
            ).map { try Self.make(from: $0) }
        }
    }

    public static func delete(taskId: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM budgets WHERE task_id = ?",
                arguments: [taskId.uuidString]
            )
        }
    }

    private static func make(from row: Row) throws -> Budget {
        Budget(
            taskId: try row.uuid("task_id"),
            maxInputTokens: row["max_input_tokens"],
            maxOutputTokens: row["max_output_tokens"],
            maxCostUSD: row["max_cost_usd"],
            maxWallSeconds: row["max_wall_seconds"],
            usedInputTokens: row["used_input_tokens"],
            usedOutputTokens: row["used_output_tokens"],
            usedCostUSD: row["used_cost_usd"],
            usedWallSeconds: row["used_wall_seconds"],
            state: try row.rawEnum("state", as: BudgetState.self),
            updatedAt: try row.date("updated_at")
        )
    }
}
