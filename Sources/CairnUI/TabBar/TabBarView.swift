import SwiftUI
import CairnTerminal

/// Main Area 顶部的 Tab Bar。spec §6.3。
/// 每个 tab 一个胶囊:左边 3pt 灰色边框 + 标题 + 关闭按钮。
/// M1.4 左边框 v1 全部灰色(Claude 蓝 / 等输入橙 / 错误红留 M2.x)。
public struct TabBarView: View {
    @Bindable var coordinator: TabsCoordinator

    public init(coordinator: TabsCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(coordinator.tabs) { tab in
                    tabPill(for: tab)
                }
                // 右侧占位(使 tab 左对齐)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func tabPill(for tab: TabSession) -> some View {
        let isActive = tab.id == coordinator.activeTabId
        return HStack(spacing: 6) {
            // 左边 3pt 灰色状态边框(v1.4 全灰,spec §6.3 后续颜色留 M2.x)
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
                    coordinator.closeTab(id: tab.id)
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
            coordinator.activateTab(id: tab.id)
        }
    }
}
