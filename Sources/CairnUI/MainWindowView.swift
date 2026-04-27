import SwiftUI
import CairnTerminal

/// Cairn 主窗口根视图。spec §6.1 三区布局。
///
/// 折叠状态由调用方(Scene)持有并通过 @Binding 注入;
/// TabsCoordinator 同样由 Scene 注入,作跨视图 tab 状态管理器。
public struct MainWindowView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var showInspector: Bool
    @Bindable var tabsCoordinator: TabsCoordinator

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        showInspector: Binding<Bool>,
        tabsCoordinator: TabsCoordinator
    ) {
        _columnVisibility = columnVisibility
        _showInspector = showInspector
        self.tabsCoordinator = tabsCoordinator
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

    /// Main Area:TabBarView + ZStack(所有 tab 的 TerminalSurface)+ StatusBar。
    private var mainArea: some View {
        VStack(spacing: 0) {
            TabBarView(coordinator: tabsCoordinator)

            Divider()

            // ZStack 渲染所有 tabs 的 terminal view,非 active 用 opacity=0
            // 保活(NSView 不被 SwiftUI 销毁,PTY + 缓冲保留)。
            ZStack {
                if tabsCoordinator.tabs.isEmpty {
                    emptyState
                } else {
                    ForEach(tabsCoordinator.tabs) { tab in
                        TerminalSurface(session: tab)
                            .opacity(tab.id == tabsCoordinator.activeTabId ? 1 : 0)
                            .allowsHitTesting(tab.id == tabsCoordinator.activeTabId)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            StatusBarView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No active tab")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Press ⌘T to open a new terminal.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview("Main window") {
    MainWindowView(
        columnVisibility: .constant(.all),
        showInspector: .constant(true),
        tabsCoordinator: TabsCoordinator()
    )
    .frame(width: 1280, height: 800)
}
#endif
