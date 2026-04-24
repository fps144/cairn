import Foundation

/// 终端标签(1 PTY 进程 + 滚动缓冲)。spec §2.1 / §5.3。
///
/// M1.1 不含 scrollBufferRef(spec §2.6 列出但 v1 不持久化,见 §5.6);
/// layoutState 独立持久化在 M1.2 的 layout_states 表。
public struct Tab: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var workspaceId: UUID
    public var title: String
    public var ptyPid: Int?
    public var state: TabState

    public init(
        id: UUID = UUID(),
        workspaceId: UUID,
        title: String,
        ptyPid: Int? = nil,
        state: TabState = .active
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.ptyPid = ptyPid
        self.state = state
    }
}

/// Tab 生命周期状态。spec §2.6 明确只有 active / closed 两态。
public enum TabState: String, Codable, CaseIterable, Sendable {
    case active
    case closed
}
