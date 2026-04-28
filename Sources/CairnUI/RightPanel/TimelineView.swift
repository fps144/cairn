import SwiftUI
import CairnCore
import CairnServices

/// Event Timeline —— Inspector 里的实时事件流面板。
/// M2.5 起:按 TimelineEntry 分派到不同 View 组件(配对卡 / 合并 / thinking / boundary / 普通行)。
public struct TimelineView: View {
    @Bindable var vm: TimelineViewModel

    public init(vm: TimelineViewModel) {
        self.vm = vm
    }

    public var body: some View {
        if vm.events.isEmpty {
            VStack(spacing: 8) {
                Text("Events stream in as Claude Code runs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Open a terminal tab, run `claude`, and talk to it — events will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.entries, id: \.id) { entry in
                            row(for: entry)
                                .id(entry.id)
                        }
                    }
                }
                .onChange(of: vm.events.count) { _, _ in
                    if let last = vm.entries.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: TimelineEntry) -> some View {
        switch entry {
        case .single(let e):
            if e.type == .assistantThinking {
                ThinkingRowView(
                    event: e,
                    isExpanded: vm.isExpanded(entry),
                    onToggle: { vm.toggle(entry.id) }
                )
            } else {
                EventRowView(event: e)
            }
        case .toolCard(let use, let result):
            ToolCardView(
                toolUse: use, toolResult: result,
                isExpanded: vm.isExpanded(entry),
                onToggle: { vm.toggle(entry.id) }
            )
        case .mergedTools(let cat, let events):
            MergedToolsView(
                category: cat, events: events,
                isExpanded: vm.isExpanded(entry),
                onToggle: { vm.toggle(entry.id) }
            )
        case .compactBoundary(let e):
            CompactBoundaryView(event: e)
        }
    }
}
