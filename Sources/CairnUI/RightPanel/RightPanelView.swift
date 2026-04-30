import SwiftUI
import CairnServices

/// Right Panel(Inspector):当前 Task 的详情 / Budget / Event Timeline。
/// spec §6.1 + §6.5-§6.6。M2.4 接入 Event Timeline(vm);其余 2 section 仍空态占位。
public struct RightPanelView: View {
    /// optional —— App 启动过程中 vm 尚未 init 时为 nil;SwiftUI 再渲后填入。
    let timelineVM: TimelineViewModel?

    public init(timelineVM: TimelineViewModel?) {
        self.timelineVM = timelineVM
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section(
                    title: "Current Task",
                    emptyLine: "No task selected."
                )

                section(
                    title: "Budget",
                    emptyLine: "Budget appears when a Task is active."
                )

                // Event Timeline 节
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Event Timeline").font(.headline)
                        Spacer()
                        if let vm = timelineVM {
                            // M2.6:显示当前 session 的生命周期状态
                            SessionStateBadge(state: vm.currentSessionState)
                        }
                    }
                    if let vm = timelineVM {
                        TimelineView(vm: vm)
                            .frame(minHeight: 240)
                    } else {
                        Text("Initializing…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
        }
    }

    private func section(title: String, emptyLine: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(emptyLine)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
#Preview {
    RightPanelView(timelineVM: nil).frame(width: 360, height: 600)
}
#endif
