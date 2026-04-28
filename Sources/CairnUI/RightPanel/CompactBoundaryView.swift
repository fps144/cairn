import SwiftUI
import CairnCore

/// compact_boundary 渲染成一条细线 + 中间小字 "context compacted HH:mm:ss"。
/// spec §6.4:"compact_boundary ─── 灰 divider"。
public struct CompactBoundaryView: View {
    let event: Event

    public init(event: Event) {
        self.event = event
    }

    public var body: some View {
        HStack(spacing: 8) {
            line
            Text("context compacted \(Self.formatTime(event.timestamp))")
                .font(.system(.caption2, design: .default))
                .foregroundStyle(.tertiary)
                .fixedSize()
            line
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
