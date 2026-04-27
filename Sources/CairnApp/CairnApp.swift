import SwiftUI
import CairnUI

@main
struct CairnApp: App {
    // 折叠状态提升到 Scene 层,让 commands 和 MainWindowView 共享。
    // 避免 NSApp.tryToPerform(toggleSidebar:) 这类 AppKit 桥接的脆弱性。
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector: Bool = true

    var body: some Scene {
        WindowGroup("Cairn") {
            MainWindowView(
                columnVisibility: $columnVisibility,
                showInspector: $showInspector
            )
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            // spec §6.7 快捷键 v1 本 milestone 实装这 2 个(其余 15 个留 M1.4+)
            // withAnimation 强制动画 —— 从 Scene-level command 改 columnVisibility
            // 时 NavigationSplitView 默认不走动画,必须显式包裹
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
        }
    }
}
