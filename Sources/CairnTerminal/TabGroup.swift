import Foundation
import Observation
import CairnCore

/// 一组 tabs 的容器(水平分屏里一列就是一个 TabGroup)。
/// @Observable @MainActor class,SplitCoordinator 持有 1-2 个。
@Observable
@MainActor
public final class TabGroup: Identifiable {
    public let id: UUID
    public private(set) var tabs: [TabSession] = []
    public var activeTabId: UUID?

    public init(id: UUID = UUID()) {
        self.id = id
    }

    /// 便利读:当前 active tab(可能 nil,如关完最后 tab 时)。
    public var activeTab: TabSession? {
        guard let id = activeTabId else { return nil }
        return tabs.first(where: { $0.id == id })
    }

    // MARK: - tabs 管理

    @discardableResult
    public func openTab(
        workspaceId: UUID,
        shell: String? = nil,
        cwd: String? = nil,
        onProcessTerminated: @escaping @MainActor (UUID) -> Void
    ) -> TabSession {
        let effectiveCwd = cwd ?? activeTab?.cwd
        var created: TabSession!
        created = TabSessionFactory.create(
            workspaceId: workspaceId,
            shell: shell,
            cwd: effectiveCwd,
            onProcessTerminated: { [weak self] _ in
                guard self != nil else { return }
                onProcessTerminated(created.id)
            }
        )
        tabs.append(created)
        activeTabId = created.id
        return created
    }

    /// 给 restore 用:不启 PTY,直接插入已构造的 session。
    /// 恢复场景由 LayoutSerializer 调用(自己构造 session 用 Factory)。
    public func appendRestoredTab(_ session: TabSession) {
        tabs.append(session)
        if activeTabId == nil {
            activeTabId = session.id
        }
    }

    public func activateTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    public func activateNextTab() {
        guard !tabs.isEmpty else { return }
        guard let current = activeTabId,
              let idx = tabs.firstIndex(where: { $0.id == current }) else {
            activeTabId = tabs.first?.id
            return
        }
        let next = (idx + 1) % tabs.count
        activeTabId = tabs[next].id
    }

    public func activatePreviousTab() {
        guard !tabs.isEmpty else { return }
        guard let current = activeTabId,
              let idx = tabs.firstIndex(where: { $0.id == current }) else {
            activeTabId = tabs.last?.id
            return
        }
        let prev = (idx - 1 + tabs.count) % tabs.count
        activeTabId = tabs[prev].id
    }

    /// 关 tab。返回 "组是否变空"(供 SplitCoordinator 决定是否合并分屏)。
    @discardableResult
    public func closeTab(id: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return tabs.isEmpty
        }
        tabs[index].terminate()
        tabs.remove(at: index)

        if activeTabId == id {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                let newIndex = max(0, index - 1)
                activeTabId = tabs[newIndex].id
            }
        }
        return tabs.isEmpty
    }

    /// 进程自然退出(不走 terminate,shell 已死)
    @discardableResult
    public func removeTabWithoutTerminate(id: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return tabs.isEmpty
        }
        tabs[index].state = .closed
        tabs.remove(at: index)

        if activeTabId == id {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                let newIndex = max(0, index - 1)
                activeTabId = tabs[newIndex].id
            }
        }
        return tabs.isEmpty
    }

    // MARK: - Test helper

    internal func _insertForTesting(_ session: TabSession) {
        tabs.append(session)
        activeTabId = session.id
    }
}
