import SwiftUI
import CairnTerminal
import CairnServices

/// Cairn 主窗口根视图。spec §6.1 三区布局 + M1.5 水平分屏 + M2.4 Timeline。
///
/// 折叠状态由调用方(Scene)持有并通过 @Binding 注入;
/// SplitCoordinator 同样由 Scene 注入,管 1-2 个 TabGroup。
/// timelineVM 是 optional:App 启动瞬态时可能为 nil(initializeDatabase 还没完成),
/// RightPanelView 里用 if let 分流。
public struct MainWindowView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var showInspector: Bool
    @Bindable var split: SplitCoordinator
    let timelineVM: TimelineViewModel?

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        showInspector: Binding<Bool>,
        split: SplitCoordinator,
        timelineVM: TimelineViewModel?
    ) {
        _columnVisibility = columnVisibility
        _showInspector = showInspector
        self.split = split
        self.timelineVM = timelineVM
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
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
        timelineVM: nil
    )
    .frame(width: 1280, height: 800)
}
#endif
