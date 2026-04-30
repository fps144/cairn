import SwiftUI
import CairnCore

/// spec §4.5 session 生命周期 5 态的视觉指示。
/// Timeline header 右上角显示。
public struct SessionStateBadge: View {
    let state: SessionState?

    public init(state: SessionState?) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var symbol: String {
        switch state {
        case .live:      return "circle.fill"
        case .idle:      return "circle.dotted"
        case .ended:     return "checkmark.circle"
        case .abandoned: return "exclamationmark.triangle.fill"
        case .crashed:   return "xmark.circle.fill"
        case .none:      return "questionmark.circle"
        }
    }

    private var color: Color {
        switch state {
        case .live:      return .green
        case .idle:      return .secondary
        case .ended:     return .secondary
        case .abandoned: return .orange
        case .crashed:   return .red
        case .none:      return .gray.opacity(0.5)
        }
    }

    private var label: String {
        switch state {
        case .live:      return "live"
        case .idle:      return "idle"
        case .ended:     return "ended"
        case .abandoned: return "abandoned"
        case .crashed:   return "crashed"
        case .none:      return "—"
        }
    }
}

#if DEBUG
#Preview("session states") {
    VStack(alignment: .leading, spacing: 8) {
        SessionStateBadge(state: .live)
        SessionStateBadge(state: .idle)
        SessionStateBadge(state: .ended)
        SessionStateBadge(state: .abandoned)
        SessionStateBadge(state: .crashed)
        SessionStateBadge(state: nil)
    }
    .padding()
}
#endif
