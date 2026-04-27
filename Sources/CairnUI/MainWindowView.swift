import SwiftUI
import CairnTerminal

/// Cairn 主窗口根视图。spec §6.1 三区布局。
///
/// 折叠状态由**调用方(Scene)持有**并通过 `@Binding` 注入 —— Scene-level
/// commands 里的 `⌘⇧T` / `⌘I` 菜单项直接 toggle 这两个 state,
/// 避免 `NSApp.tryToPerform(toggleSidebar:)` 这类 AppKit 桥接的脆弱性。
///
/// - Sidebar:Task 列表(M1.3 占位);280pt 默认宽,`⌘⇧T` 折叠
/// - Main Area:TerminalSurface + Tab Bar + Status Bar
/// - Right Panel (Inspector):Current Task / Budget / Timeline(M1.3 占位);360pt 默认宽,`⌘I` 折叠
public struct MainWindowView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var showInspector: Bool

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        showInspector: Binding<Bool>
    ) {
        _columnVisibility = columnVisibility
        _showInspector = showInspector
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

    /// Main Area:Tab Bar(v1.3 占位)+ Terminal + Status Bar。
    private var mainArea: some View {
        VStack(spacing: 0) {
            // Tab Bar 占位(M1.4 填充真实 tabs)
            HStack(spacing: 8) {
                Text("~ (zsh)")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Terminal — 直接用 CairnTerminal 模块的 TerminalSurface
            TerminalSurface()

            Divider()

            StatusBarView()
        }
    }
}

#if DEBUG
#Preview("Main window") {
    // Preview 用 .constant 提供静态 Binding
    MainWindowView(
        columnVisibility: .constant(.all),
        showInspector: .constant(true)
    )
    .frame(width: 1280, height: 800)
}
#endif
