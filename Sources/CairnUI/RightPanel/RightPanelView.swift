import SwiftUI

/// Right Panel(Inspector):当前 Task 的详情 / Budget / Event Timeline。
/// spec §6.1 + §6.5-§6.6。M1.3 只做 3 小节空态占位。
public struct RightPanelView: View {
    public init() {}

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

                section(
                    title: "Event Timeline",
                    emptyLine: "Events stream in as Claude Code runs."
                )
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
    RightPanelView().frame(width: 360, height: 600)
}
#endif
