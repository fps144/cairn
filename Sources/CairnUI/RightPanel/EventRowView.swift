import SwiftUI
import CairnCore

/// Event Timeline 单行。spec §6.4 —— icon + summary + 时间戳。
/// M2.4 是"基础"版本;合并("Read × 3")/ 折叠交互是 M2.5。
public struct EventRowView: View {
    let event: Event

    public init(event: Event) {
        self.event = event
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: EventStyleMap.symbol(for: event))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EventStyleMap.tint(for: event))
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)

            Text(event.summary)
                .font(.system(.caption, design: .default))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.formatTime(event.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        // error 事件:轻微红色背景,视觉上一眼识别
        .background(
            event.type == .error
                ? Color.red.opacity(0.08)
                : Color.clear
        )
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

#if DEBUG
#Preview("event-rows") {
    VStack(alignment: .leading, spacing: 0) {
        EventRowView(event: Event(
            sessionId: UUID(), type: .userMessage,
            timestamp: Date(), lineNumber: 1, summary: "hello, fix the auth bug"
        ))
        EventRowView(event: Event(
            sessionId: UUID(), type: .toolUse, category: .shell,
            toolName: "Bash", toolUseId: "tu_1",
            timestamp: Date(), lineNumber: 2, summary: "Bash(command=ls -la)"
        ))
        EventRowView(event: Event(
            sessionId: UUID(), type: .assistantText,
            timestamp: Date(), lineNumber: 3, summary: "Let me check the auth module..."
        ))
        EventRowView(event: Event(
            sessionId: UUID(), type: .apiUsage,
            timestamp: Date(), lineNumber: 4, summary: "in=1200 out=340 cache=800"
        ))
        EventRowView(event: Event(
            sessionId: UUID(), type: .error,
            timestamp: Date(), lineNumber: 5, summary: "tool_result reported error"
        ))
    }
    .frame(width: 360)
    .padding()
}
#endif
