import SwiftUI
import CairnCore
import CairnTerminal
import CairnServices

/// Cairn 主窗口根视图。spec §6.1 三区布局 + M1.5 水平分屏 + M2.4 Timeline + M3.1 Sidebar Task 列表。
///
/// 折叠状态由调用方(Scene)持有并通过 @Binding 注入;
/// SplitCoordinator 同样由 Scene 注入,管 1-2 个 TabGroup。
/// timelineVM / taskListVM 是 optional:App 启动瞬态时可能为 nil(initializeDatabase 还没完成),
/// 子 view 里用 if let 分流。
public struct MainWindowView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var showInspector: Bool
    @Bindable var split: SplitCoordinator
    let timelineVM: TimelineViewModel?
    let taskListVM: TaskListViewModel?

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        showInspector: Binding<Bool>,
        split: SplitCoordinator,
        timelineVM: TimelineViewModel?,
        taskListVM: TaskListViewModel?
    ) {
        _columnVisibility = columnVisibility
        _showInspector = showInspector
        self.split = split
        self.timelineVM = timelineVM
        self.taskListVM = taskListVM
    }

    /// M2.6:active tab 的 boundClaudeSessionId 作为 .task(id:) 的识别 key。
    /// boundClaudeSessionId 变化(新绑定 / 解绑 / 切 tab)时,task 重跑
    /// `timelineVM.switchSession`。首次 appear 也触发(`.task(id:)` 规则)。
    private var activeBoundSessionKey: UUID? {
        guard split.activeGroupIndex < split.groups.count else { return nil }
        return split.groups[split.activeGroupIndex].activeTab?.boundClaudeSessionId
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                vm: taskListVM,
                activeBoundSessionId: activeBoundSessionKey,
                onTapTask: { task in
                    handleTaskTap(task)
                }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
        } detail: {
            mainArea
        }
        .inspector(isPresented: $showInspector) {
            RightPanelView(timelineVM: timelineVM)
                .inspectorColumnWidth(min: 280, ideal: 360, max: 500)
        }
        .toolbar {
            CairnToolbarContent(showInspector: $showInspector)
        }
        .task(id: activeBoundSessionKey) {
            if let vm = timelineVM {
                await vm.switchSession(activeBoundSessionKey)
            }
        }
    }

    /// Sidebar 点击 task 行:切到对应 tab(若 tab 还在);否则直接切 timeline。
    /// 切 active tab 后,MainWindowView .task(id: activeBoundSessionKey)
    /// 自动跟随重跑 timelineVM.switchSession,无需此处显式触发。
    private func handleTaskTap(_ task: CairnTask) {
        guard let sid = task.sessionIds.first else { return }
        if let hit = split.findTab(boundSessionId: sid) {
            split.activeGroupIndex = hit.groupIndex
            split.groups[hit.groupIndex].activateTab(id: hit.tabId)
        } else {
            // M3.6 历史 task fallback:tab 已不在,直接切 timeline 浏览历史
            Task { await timelineVM?.switchSession(sid) }
        }
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            splitContent
            Divider()
            StatusBarView()
        }
    }

    @ViewBuilder
    private var splitContent: some View {
        if split.groups.count >= 2 {
            HSplitView {
                TabGroupView(
                    group: split.groups[0],
                    isActiveGroup: split.activeGroupIndex == 0,
                    onTapActivate: { split.activeGroupIndex = 0 },
                    onCloseTab: { [split] tabId in
                        withAnimation {
                            split.closeTab(in: split.groups[0], id: tabId)
                        }
                    }
                )
                TabGroupView(
                    group: split.groups[1],
                    isActiveGroup: split.activeGroupIndex == 1,
                    onTapActivate: { split.activeGroupIndex = 1 },
                    onCloseTab: { [split] tabId in
                        withAnimation {
                            // groups 可能在回调前已被 collapse;安全查找 group
                            if split.groups.count > 1 {
                                split.closeTab(in: split.groups[1], id: tabId)
                            }
                        }
                    }
                )
            }
        } else {
            TabGroupView(
                group: split.groups[0],
                isActiveGroup: true,
                onTapActivate: {},
                onCloseTab: { [split] tabId in
                    withAnimation {
                        split.closeTab(in: split.groups[0], id: tabId)
                    }
                }
            )
        }
    }
}

#if DEBUG
#Preview("Main window") {
    MainWindowView(
        columnVisibility: .constant(.all),
        showInspector: .constant(true),
        split: SplitCoordinator(),
        timelineVM: nil,
        taskListVM: nil
    )
    .frame(width: 1280, height: 800)
}
#endif
