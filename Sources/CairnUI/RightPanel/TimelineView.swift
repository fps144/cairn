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
        if vm.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading events…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        } else if vm.events.isEmpty {
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
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(vm.entries, id: \.id) { entry in
                                row(for: entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .onChange(of: vm.events.count) { _, _ in
                        // M2.7:用户 pin 暂停时不打断手滚看历史
                        guard !vm.isAutoScrollPaused, let last = vm.entries.last else { return }
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }

                    // M2.7:右下角浮起 pin 按钮 —— 控制 auto-scroll 暂停/恢复
                    Button {
                        vm.toggleAutoScrollPaused()
                        // 恢复时立即滚到底
                        if !vm.isAutoScrollPaused, let last = vm.entries.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    } label: {
                        Image(systemName: vm.isAutoScrollPaused
                              ? "pin.slash.fill"
                              : "arrow.down.to.line")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(vm.isAutoScrollPaused ? .orange : .secondary)
                            .frame(width: 26, height: 26)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(vm.isAutoScrollPaused
                          ? "Auto-scroll paused — click to resume"
                          : "Pause auto-scroll")
                    .padding(8)
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
