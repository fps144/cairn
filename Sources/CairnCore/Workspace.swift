import Foundation

/// Cairn 中的工作空间:一个项目的根目录 + 关联状态。
///
/// spec §2.1:Workspace 包含多个 Tab / Session,拥有窗口/布局状态。
/// M1.1 只定义纯数据;布局状态(LayoutState)留 M1.3。
public struct Workspace: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var cwd: String
    public let createdAt: Date
    public var lastActiveAt: Date
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        cwd: String,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.archivedAt = archivedAt
    }
}
