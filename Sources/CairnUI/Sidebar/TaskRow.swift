import SwiftUI
import CairnCore

/// Sidebar 单个 Task 行。spec §6.2:状态 dot + title + relative time。
/// M3.2 加右键菜单(归档/重命名/合并);M3.3 加 Budget %。
struct TaskRow: View {
    let task: CairnTask
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(relativeTimestamp(from: task.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .active:
            Circle().fill(.blue).frame(width: 7, height: 7)
        case .completed:
            Circle().stroke(.gray, lineWidth: 1).frame(width: 7, height: 7)
        case .abandoned:
            Image(systemName: "circle.slash")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
        case .archived:
            Image(systemName: "tray.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func relativeTimestamp(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 86400 * 30 { return "\(Int(interval / 86400))d" }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    }
}
