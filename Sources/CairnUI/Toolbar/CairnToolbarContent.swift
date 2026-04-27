import SwiftUI

/// 主窗口顶部工具条。spec §6.1 顶端示意。
/// 本 milestone:workspace 选择器占位 + 通知 / 设置 / Inspector 切换按钮。
///
/// **命名注**:SwiftUI 自身有 `ToolbarContent` 协议;我们这个 struct
/// 取名 `CairnToolbarContent` 以避 `struct X: X` 形式的递归类型歧义。
public struct CairnToolbarContent: ToolbarContent {
    @Binding var showInspector: Bool

    public init(showInspector: Binding<Bool>) {
        _showInspector = showInspector
    }

    public var body: some ToolbarContent {
        // 左侧:Workspace 选择器占位
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("New Workspace...") {
                    // M3.5 填充
                }
                Divider()
                Text("No workspaces yet")
            } label: {
                Label("Workspace", systemImage: "folder")
            }
        }

        // 右侧:系统按钮组
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                // M4.3 诊断 / 通知中心
            } label: {
                Label("Notifications", systemImage: "bell")
            }
            .help("Notifications")

            Button {
                // M4.1 Settings 页
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings")

            Button {
                showInspector.toggle()
            } label: {
                Label("Toggle Inspector",
                      systemImage: showInspector
                        ? "sidebar.right"
                        : "sidebar.trailing")
            }
            // ⌘I 快捷键在 Scene commands 里绑,此处不重复(避免歧义)
            .help("Toggle inspector (⌘I)")
        }
    }
}
