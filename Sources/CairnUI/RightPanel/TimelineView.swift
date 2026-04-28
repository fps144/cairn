import SwiftUI
import CairnCore
import CairnServices

/// Event Timeline —— Inspector 里的实时事件流面板。
/// spec §6.4;M2.4 基础版本(无合并 / 折叠 / 搜索)。
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
                    // Event 有 `let id: UUID` 但未 conform Identifiable;
                    // 用显式 keyPath 避免改 CairnCore。
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.events, id: \.id) { event in
                            EventRowView(event: event)
                                .id(event.id)
                            Divider().opacity(0.3)
                        }
                    }
                }
                .onChange(of: vm.events.count) { _, _ in
                    if let last = vm.events.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }
}
