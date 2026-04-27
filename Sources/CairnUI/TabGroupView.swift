import SwiftUI
import CairnTerminal

/// 一个分屏 = TabBar + ZStack(所有 tab 的 TerminalSurface)。
/// 空态时显示提示。active 分屏有淡色 accent 边框。
public struct TabGroupView: View {
    @Bindable var group: TabGroup
    let isActiveGroup: Bool
    let onTapActivate: () -> Void

    public init(
        group: TabGroup,
        isActiveGroup: Bool,
        onTapActivate: @escaping () -> Void
    ) {
        self.group = group
        self.isActiveGroup = isActiveGroup
        self.onTapActivate = onTapActivate
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabBarView(group: group)

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
        .overlay(
            Rectangle()
                .stroke(isActiveGroup ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        )
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
