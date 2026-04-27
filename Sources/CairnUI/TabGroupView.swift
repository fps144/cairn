import SwiftUI
import CairnTerminal

/// 一个分屏 = TabBar + ZStack(所有 tab 的 TerminalSurface)。
/// 空态时显示提示。active 分屏有淡色 accent 边框。
public struct TabGroupView: View {
    @Bindable var group: TabGroup
    let isActiveGroup: Bool
    let onTapActivate: () -> Void
    let onCloseTab: (UUID) -> Void

    public init(
        group: TabGroup,
        isActiveGroup: Bool,
        onTapActivate: @escaping () -> Void,
        onCloseTab: @escaping (UUID) -> Void
    ) {
        self.group = group
        self.isActiveGroup = isActiveGroup
        self.onTapActivate = onTapActivate
        self.onCloseTab = onCloseTab
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabBarView(group: group, onCloseTab: onCloseTab)

            Divider()

            ZStack {
                if group.tabs.isEmpty {
                    emptyState
                } else {
                    ForEach(group.tabs) { tab in
                        TerminalSurface(session: tab)
                            .opacity(tab.id == group.activeTabId ? 1 : 0)
                            .allowsHitTesting(tab.id == group.activeTabId)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // active 分屏用顶部细条做视觉区分,替代 M1.5 初稿的全边框
        // (旧方案 .stroke accent 0.5 lineWidth 2 —— 在深色背景上偏重且
        // 和窗口 chrome 冲突。细条方案更 native macOS 风格。)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isActiveGroup
                      ? AnyShapeStyle(Color.accentColor)
                      : AnyShapeStyle(Color.clear))
                .frame(height: 2)
                .allowsHitTesting(false)
        }
        .onTapGesture {
            onTapActivate()
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
