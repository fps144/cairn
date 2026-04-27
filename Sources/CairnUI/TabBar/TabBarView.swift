import SwiftUI
import CairnTerminal

/// Main Area 顶部的 Tab Bar。spec §6.3。
/// M1.5 改为接 TabGroup;onCloseTab 由父(TabGroupView)注入,路由到
/// SplitCoordinator 以触发 collapseEmptyGroups(否则关 B 的最后一个 tab
/// 不会自动收拢分屏)。
public struct TabBarView: View {
    @Bindable var group: TabGroup
    let onCloseTab: (UUID) -> Void

    public init(
        group: TabGroup,
        onCloseTab: @escaping (UUID) -> Void
    ) {
        self.group = group
        self.onCloseTab = onCloseTab
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(group.tabs) { tab in
                    tabPill(for: tab)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func tabPill(for tab: TabSession) -> some View {
        let isActive = tab.id == group.activeTabId
        return HStack(spacing: 6) {
            Rectangle()
                .fill(Color.secondary)
                .frame(width: 3, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))

            Text(tab.title)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            Button {
                withAnimation {
                    onCloseTab(tab.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        isActive ? Color.secondary.opacity(0.15) : .clear,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .help("Close tab (⌘W)")
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(
            isActive
                ? AnyShapeStyle(.regularMaterial)
                : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            group.activateTab(id: tab.id)
        }
    }
}
