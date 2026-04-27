import SwiftUI
import CairnUI
import CairnTerminal

@main
struct CairnApp: App {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector: Bool = true
    @State private var tabsCoordinator = TabsCoordinator()

    /// v1 没有真实 workspace 管理,用固定 UUID 作 "default workspace"
    /// 占位。M3.5 Workspace 管理就位后替换为真实 workspace id。
    private let defaultWorkspaceId = UUID()

    var body: some Scene {
        // 用显式 content: 标签消歧义(macOS 14+ WindowGroup 有 content: 和
        // makeContent: 两个 init 签名,trailing closure 无法唯一匹配)
        WindowGroup("Cairn", content: {
            MainWindowView(
                columnVisibility: $columnVisibility,
                showInspector: $showInspector,
                tabsCoordinator: tabsCoordinator
            )
            .onAppear {
                // 启动时默认开一个 tab(方便用户)
                if tabsCoordinator.tabs.isEmpty {
                    tabsCoordinator.openTab(workspaceId: defaultWorkspaceId)
                }
            }
        })
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    withAnimation {
                        columnVisibility =
                            (columnVisibility == .detailOnly) ? .all : .detailOnly
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Toggle Inspector") {
                    withAnimation {
                        showInspector.toggle()
                    }
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            // M1.4 Tab 快捷键(spec §6.7)
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    withAnimation {
                        // 显式 discard:openTab 返回 TabSession,否则
                        // withAnimation 泛型 Result 推断成 TabSession 与
                        // Button action 的 Void 冲突。
                        _ = tabsCoordinator.openTab(workspaceId: defaultWorkspaceId)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    withAnimation {
                        tabsCoordinator.closeActiveTab()
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Next Tab") {
                    tabsCoordinator.activateNextTab()
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Previous Tab") {
                    tabsCoordinator.activatePreviousTab()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}
