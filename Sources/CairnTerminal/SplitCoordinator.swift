import Foundation
import Observation
import CairnCore

/// 水平分屏(最多 2 分屏)管理器。每分屏 = 一个 TabGroup。
/// spec §5.3:最多水平 2 分屏,每侧多 tab;不垂直分屏。
@Observable
@MainActor
public final class SplitCoordinator {
    public private(set) var groups: [TabGroup] = []
    public var activeGroupIndex: Int = 0

    public init() {
        // 默认 1 个空组(不变式:至少 1 组)
        groups = [TabGroup()]
    }

    /// 便利读:当前 active group。
    public var activeGroup: TabGroup {
        groups[activeGroupIndex]
    }

    // MARK: - 分屏管理

    /// ⌘⇧D 触发。若已 2 分屏则无效;否则新建分屏 + 开一个新 tab(继承 active tab cwd)。
    public func splitHorizontal(
        workspaceId: UUID,
        onProcessTerminated: @escaping @MainActor (UUID) -> Void
    ) {
        guard groups.count < 2 else { return }
        let newGroup = TabGroup()
        newGroup.openTab(
            workspaceId: workspaceId,
            cwd: activeGroup.activeTab?.cwd,
            onProcessTerminated: onProcessTerminated
        )
        groups.append(newGroup)
        activeGroupIndex = groups.count - 1
    }

    /// 移除所有空分屏,若全空则保留 1 个空组(不变式:至少 1 组)。
    public func collapseEmptyGroups() {
        guard groups.count > 1 else { return }
        let nonEmpty = groups.filter { !$0.tabs.isEmpty }
        if nonEmpty.count < groups.count {
            groups = nonEmpty.isEmpty ? [TabGroup()] : nonEmpty
            activeGroupIndex = min(activeGroupIndex, groups.count - 1)
        }
    }

    /// 关 active tab;若分组因此变空,自动 collapse。
    public func closeActiveTab() {
        guard let activeId = activeGroup.activeTabId else { return }
        let wasEmpty = activeGroup.closeTab(id: activeId)
        if wasEmpty {
            collapseEmptyGroups()
        }
    }

    /// 关任意 group 里的任意 tab(UI × 按钮用)。统一入口保证 close 后
    /// 触发 collapseEmptyGroups,避免空分屏残留。
    public func closeTab(in group: TabGroup, id: UUID) {
        let wasEmpty = group.closeTab(id: id)
        if wasEmpty {
            collapseEmptyGroups()
        }
    }

    /// shell 进程自然退出回调:找到对应 tab 并移除;若组空了 collapse。
    public func handleTabTerminated(tabId: UUID) {
        for group in groups {
            if group.tabs.contains(where: { $0.id == tabId }) {
                let wasEmpty = group.removeTabWithoutTerminate(id: tabId)
                if wasEmpty {
                    collapseEmptyGroups()
                }
                return
            }
        }
    }

    // MARK: - Replace groups(restore + 测试共用)

    /// 用给定 groups 替换当前状态。LayoutSerializer.restore 和测试都用。
    /// activeGroupIndex clamp 到有效范围;空数组时复位到 0 并塞一个空组
    /// (保证不变式"至少 1 组")。
    public func replaceGroups(_ newGroups: [TabGroup], activeIndex: Int = 0) {
        groups = newGroups.isEmpty ? [TabGroup()] : newGroups
        activeGroupIndex = max(0, min(activeIndex, groups.count - 1))
    }
}
