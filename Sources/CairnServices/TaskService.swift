import Foundation
import CairnCore
import CairnStorage

/// Task 业务层:findOrCreate(broker.onBind 触发 1:1 Task 自动创建)。
///
/// 策略:1 session = 1 task(spec §2.2 v1 默认)。
/// Title 派生:`{cwd 末段} @ {MM-dd HH:mm}`(本地时区);
/// cwd 缺失或空字符串 fallback "Untitled @ ..."。
public enum TaskService {
    /// session 已有 task → 返回;否则新建并落 DB。
    public static func findOrCreate(
        sessionId: UUID,
        workspaceId: UUID,
        cwd: String?,
        now: Date = Date(),
        in db: CairnDatabase
    ) async throws -> CairnTask {
        if let existing = try await TaskDAO.fetchTaskBySessionId(sessionId, in: db) {
            return existing
        }
        let task = CairnTask(
            workspaceId: workspaceId,
            title: makeTitle(cwd: cwd, now: now),
            status: .active,
            sessionIds: [sessionId],
            createdAt: now,
            updatedAt: now
        )
        try await TaskDAO.upsert(task, in: db)
        return task
    }

    /// 派生 title:`{cwd 末段} @ {MM-dd HH:mm}` 或 `Untitled @ ...`,≤ 60 字符。
    /// internal 暴露给单测;正常调用方走 findOrCreate。
    static func makeTitle(cwd: String?, now: Date) -> String {
        let stamp = now.formatted(
            .dateTime.month(.twoDigits).day(.twoDigits).hour().minute()
        )
        let head: String
        if let cwd, !cwd.isEmpty {
            let last = (cwd as NSString).lastPathComponent
            head = last.isEmpty ? "Untitled" : last
        } else {
            head = "Untitled"
        }
        let raw = "\(head) @ \(stamp)"
        return raw.count > 60 ? String(raw.prefix(59)) + "…" : raw
    }
}
