import Foundation
import Observation
import CairnCore
import CairnStorage

/// Sidebar 的 Task list state。spec §6.2。
///
/// 启动时 `reload(workspaceId:)` 拉全;broker.onBind 时外部调 `upsert` 增量。
/// 高亮派生:基于 active tab 的 boundClaudeSessionId 反推,vm 不存 selectedTaskId
/// (单一 source-of-truth,Tab 始终是用户操作单元)。
@Observable
@MainActor
public final class TaskListViewModel {
    public private(set) var tasks: [CairnTask] = []
    public private(set) var currentWorkspaceId: UUID?

    private let database: CairnDatabase

    public init(database: CairnDatabase) {
        self.database = database
    }

    /// 初次进入 / workspace 切换(M3.5)时调。fetchAll 已按 updated_at DESC 排序。
    public func reload(workspaceId: UUID) async {
        currentWorkspaceId = workspaceId
        do {
            tasks = try await TaskDAO.fetchAll(
                workspaceId: workspaceId,
                in: database
            )
        } catch {
            tasks = []
        }
    }

    /// broker.onBind hook 增量(外部已通过 TaskService.findOrCreate 落 DB)。
    /// 已有 id 删除后再插顶,保证 update 时仍按 updatedAt DESC 顺序
    /// (M3.1 内 task 不会 update,但 M3.x 升级一致)。
    public func upsert(_ task: CairnTask) {
        // 跨 workspace 来的 task 忽略(防错绑)
        guard task.workspaceId == currentWorkspaceId else { return }
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks.remove(at: idx)
        }
        tasks.insert(task, at: 0)
    }

    /// 当前 active tab 的 sessionId 派生 highlighted task。
    /// nil sessionId / 找不到都返回 nil(Sidebar 无高亮)。
    public func highlightedTaskId(forActiveSessionId sessionId: UUID?) -> UUID? {
        guard let sessionId else { return nil }
        return tasks.first(where: { $0.sessionIds.contains(sessionId) })?.id
    }
}
