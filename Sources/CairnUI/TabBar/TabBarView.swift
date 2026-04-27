import SwiftUI
import CairnTerminal

/// Main Area 顶部的 Tab Bar。spec §6.3。
/// M1.5 改为接 TabGroup(原 TabsCoordinator 已拆成 TabGroup + SplitCoordinator)。
public struct TabBarView: View {
    @Bindable var group: TabGroup

    public init(group: TabGroup) {
        self.group = group
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
                    _ = group.closeTab(id: tab.id)
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
