import Foundation

/// 用户意图工作单元。spec §2.1 "Task 是一等实体"。
///
/// **命名注**:本类型对应 spec 的"Task"。Swift 标准库 `Task` 是结构化并发原语,
/// 为避免命名冲突,CairnCore 公开类型名为 `CairnTask`。UI 层仍向用户展示 "Task"。
///
/// spec §2.2:Task has-many Sessions(1:N),v1 UI 默认 1:1。schema 从 day 1
/// 支持 `sessionIds: [UUID]` 数组,v1 长度恒为 1,v1.5+ 支持"attach session
/// to existing task"。
public struct CairnTask: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var workspaceId: UUID
    public var title: String
    public var intent: String?
    public var status: TaskStatus
    public var sessionIds: [UUID]
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        workspaceId: UUID,
        title: String,
        intent: String? = nil,
        status: TaskStatus = .active,
        sessionIds: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.intent = intent
        self.status = status
        self.sessionIds = sessionIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

/// Task 生命周期状态(4 态)。spec §2.6。
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case active
    case completed
    case abandoned
    case archived
}
