import Foundation
import Observation
import CairnCore

/// 多 tab 管理器。@MainActor @Observable,UI 订阅 tabs / activeTabId 变化。
/// Scene-level 注入(见 CairnApp.swift)。
@Observable
@MainActor
public final class TabsCoordinator {
    public private(set) var tabs: [TabSession] = []
    public var activeTabId: UUID?

    public init() {}

    /// 新建 tab 并设为 active。
    /// - Parameters:
    ///   - workspaceId: 所属 workspace;v1 无 workspace 时用占位 UUID
    ///   - shell / cwd:可选;nil 则继承 active tab 的 cwd,最终兜底 $HOME / $SHELL
    @discardableResult
    public func openTab(
        workspaceId: UUID,
        shell: String? = nil,
        cwd: String? = nil
    ) -> TabSession {
        let effectiveCwd = cwd ?? activeTab?.cwd
        var createdSession: TabSession!
        createdSession = TabSessionFactory.create(
            workspaceId: workspaceId,
            shell: shell,
            cwd: effectiveCwd,
            onProcessTerminated: { [weak self] _ in
                guard let self else { return }
                // shell exit → 自动把 tab 从列表移除(不走 terminate,
                // 进程已经自己退了)。
                self.removeTabWithoutTerminate(id: createdSession.id)
            }
        )
        tabs.append(createdSession)
        activeTabId = createdSession.id
        return createdSession
    }

    /// 关闭 tab。强杀 PTY,从 tabs 列表移除。
    /// 若关闭的是 active tab,activeTabId 切到最近的另一个 tab(前驱优先,否则后继),
    /// 全空则置 nil。
    public func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].terminate()
        tabs.remove(at: index)

        if activeTabId == id {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                // 优先切到关闭位置的前驱,否则用原位置(现在是后继)
                let newIndex = max(0, index - 1)
                activeTabId = tabs[newIndex].id
            }
        }
    }

    /// 内部用:tab 进程自然退出时,从列表移除(不再调 terminate)。
    private func removeTabWithoutTerminate(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
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
    }

    /// 切换到指定 id。若 id 不在 tabs 中,无效果。
    public func activateTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    /// ⌘L:下一个 tab(循环)。
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

    /// ⌘⇧L:上一个 tab(循环)。
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

    /// 关闭当前 active tab(⌘W 用)。
    public func closeActiveTab() {
        guard let id = activeTabId else { return }
        closeTab(id: id)
    }

    /// 便利读取当前 active tab。
    public var activeTab: TabSession? {
        guard let id = activeTabId else { return nil }
        return tabs.first(where: { $0.id == id })
    }
}

// MARK: - Test helper

extension TabsCoordinator {
    /// 仅测试用:直接注入已构造的 TabSession,跳过 PTY 进程启动。
    /// `@testable import CairnTerminal` 可访问。
    ///
    /// 不包 `#if DEBUG` —— SPM 不自动定义 DEBUG 宏,`#if DEBUG` 在 SPM 下
    /// 永远 false,会让 @testable 测试找不到此方法。internal 访问级别足够
    /// 限制外部调用。
    internal func _insertForTesting(_ session: TabSession) {
        tabs.append(session)
        activeTabId = session.id
    }
}
