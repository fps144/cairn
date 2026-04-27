import SwiftUI

/// Sidebar:Task 列表(按 Workspace 分组)。spec §6.2。
/// M1.3 只做空态占位;真实 Task 项由 M3.1+ 填充。
public struct SidebarView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 筛选栏(v1.3 占位)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Search tasks")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // 空态内容
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("No workspaces yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Tasks from your Claude Code sessions will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Tasks")
    }
}

#if DEBUG
#Preview {
    SidebarView().frame(width: 280, height: 600)
}
#endif
