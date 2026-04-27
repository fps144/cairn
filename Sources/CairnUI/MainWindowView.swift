import SwiftUI
import CairnTerminal

/// Cairn 主窗口根视图。spec §6.1 三区布局 + M1.5 水平分屏。
///
/// 折叠状态由调用方(Scene)持有并通过 @Binding 注入;
/// SplitCoordinator 同样由 Scene 注入,管 1-2 个 TabGroup。
public struct MainWindowView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var showInspector: Bool
    @Bindable var split: SplitCoordinator

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        showInspector: Binding<Bool>,
        split: SplitCoordinator
    ) {
        _columnVisibility = columnVisibility
        _showInspector = showInspector
        self.split = split
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
        } detail: {
            mainArea
        }
        .inspector(isPresented: $showInspector) {
            RightPanelView()
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
                    onTapActivate: { split.activeGroupIndex = 0 }
                )
                TabGroupView(
                    group: split.groups[1],
                    isActiveGroup: split.activeGroupIndex == 1,
                    onTapActivate: { split.activeGroupIndex = 1 }
                )
            }
        } else {
            TabGroupView(
                group: split.groups[0],
                isActiveGroup: true,
                onTapActivate: {}
            )
        }
    }
}

#if DEBUG
#Preview("Main window") {
    MainWindowView(
        columnVisibility: .constant(.all),
        showInspector: .constant(true),
        split: SplitCoordinator()
    )
    .frame(width: 1280, height: 800)
}
#endif
