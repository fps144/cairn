import SwiftUI
import CairnCore

/// 窗口底部状态栏:cwd / git branch(v1 占位)。spec §6.1。
public struct StatusBarView: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 16) {
            Label("~", systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            // 引用 CairnCore.scaffoldVersion 避免硬编码 —— bump 版本时自动跟随
            Text("Cairn v\(CairnCore.scaffoldVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
