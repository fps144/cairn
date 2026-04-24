import Foundation

/// Claude Code 会话(以 Claude 的 sessionId UUID 唯一标识)。
///
/// spec §2.1:Claude Code 拥有 session 状态,Cairn 只观察 / 缓存元数据。
/// spec §2.6:含 byteOffset 增量解析游标;isImported 标记是否从历史 JSONL 扫出。
public struct Session: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var workspaceId: UUID
    public var jsonlPath: String
    public var startedAt: Date
    public var endedAt: Date?
    public var byteOffset: Int64
    public var lastLineNumber: Int64
    public var modelUsed: String?
    public var isImported: Bool
    public var state: SessionState

    public init(
        id: UUID = UUID(),
        workspaceId: UUID,
        jsonlPath: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        byteOffset: Int64 = 0,
        lastLineNumber: Int64 = 0,
        modelUsed: String? = nil,
        isImported: Bool = false,
        state: SessionState = .live
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.jsonlPath = jsonlPath
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.byteOffset = byteOffset
        self.lastLineNumber = lastLineNumber
        self.modelUsed = modelUsed
        self.isImported = isImported
        self.state = state
    }
}

/// Session 生命周期状态(5 态)。
///
/// spec §4.5 判据(M0.1 probe 修订后):
/// - `.live`: mtime < 60s
/// - `.idle`: mtime 60s-5min
/// - `.ended`: mtime > 5min 且无悬挂 tool_use(不要求末条是 assistant,M0.1 修订)
/// - `.abandoned`: mtime > 30min 且含未配对悬挂 tool_use
/// - `.crashed`: 文件被删除
public enum SessionState: String, Codable, CaseIterable, Sendable {
    case live
    case idle
    case ended
    case abandoned
    case crashed
}
