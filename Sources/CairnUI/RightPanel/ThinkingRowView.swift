import SwiftUI
import CairnCore

/// assistant_thinking 默认折叠。折叠态 "thinking (N chars)",展开看完整。
/// spec §6.4:"assistant_thinking 灰,折叠"。
public struct ThinkingRowView: View {
    let event: Event
    let isExpanded: Bool
    let onToggle: () -> Void

    public init(event: Event, isExpanded: Bool, onToggle: @escaping () -> Void) {
        self.event = event
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "brain")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)

                Text(isExpanded
                     ? "thinking"
                     : "thinking (\(event.summary.count) chars)")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }

            if isExpanded {
                Text(event.summary)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.secondary)
                    .italic()
                    .textSelection(.enabled)
                    .lineLimit(30)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)
            }
        }
    }
}
