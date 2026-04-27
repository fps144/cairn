import Foundation
import Observation

/// 主窗口跨视图状态。本 milestone 仅管"折叠初始值"和"当前 workspace"占位。
/// M3.5 Workspace 管理时扩充。
@Observable
@MainActor
public final class MainWindowViewModel {
    /// 当前选中的 workspace id。M1.3 恒 nil,为 M3.5 预留。
    public var currentWorkspaceId: UUID?

    /// 记录用户上次是否把 Sidebar 折叠(M1.5 做布局持久化时再 sync 到
    /// CairnStorage.LayoutStateDAO)。本 milestone 仅作内存态。
    public var sidebarCollapsed: Bool
    public var inspectorCollapsed: Bool

    public init(
        currentWorkspaceId: UUID? = nil,
        sidebarCollapsed: Bool = false,
        inspectorCollapsed: Bool = false
    ) {
        self.currentWorkspaceId = currentWorkspaceId
        self.sidebarCollapsed = sidebarCollapsed
        self.inspectorCollapsed = inspectorCollapsed
    }

    public func toggleSidebar() {
        sidebarCollapsed.toggle()
    }

    public func toggleInspector() {
        inspectorCollapsed.toggle()
    }
}
