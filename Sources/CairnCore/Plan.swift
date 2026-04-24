import Foundation

/// Task 的执行计划。spec §2.6。
///
/// 来源有三:TodoWrite 工具产出、`.claude/plans/*.md` 文件、用户手动输入。
/// M1.1 提供数据结构,实际解析(markdown → steps)留 M3.4 PlanWatcher。
public struct Plan: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var taskId: UUID
    public var source: PlanSource
    public var steps: [PlanStep]
    public var markdownRaw: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        taskId: UUID,
        source: PlanSource,
        steps: [PlanStep] = [],
        markdownRaw: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.source = source
        self.steps = steps
        self.markdownRaw = markdownRaw
        self.updatedAt = updatedAt
    }
}

/// Plan 的数据来源。spec §2.6。
public enum PlanSource: String, Codable, CaseIterable, Sendable {
    case todoWrite = "todo_write"
    case planMd = "plan_md"
    case manual
}

/// Plan 中的单步。spec §2.6 `{id, content, status, priority}`。
public struct PlanStep: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var content: String
    public var status: PlanStepStatus
    public var priority: PlanStepPriority

    public init(
        id: UUID = UUID(),
        content: String,
        status: PlanStepStatus = .pending,
        priority: PlanStepPriority = .medium
    ) {
        self.id = id
        self.content = content
        self.status = status
        self.priority = priority
    }
}

/// PlanStep 执行状态(3 态,对齐 Claude Code TodoWrite 语义)。
public enum PlanStepStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}

/// PlanStep 优先级。TodoWrite 规范。
public enum PlanStepPriority: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}
