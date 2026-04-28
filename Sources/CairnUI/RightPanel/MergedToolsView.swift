import SwiftUI
import CairnCore

/// 连续同 category 未配对 tool_use 的合并视图("Read × 3")。
/// 折叠态一行 + category icon + 计数;展开态 N 个 summary 小行。
public struct MergedToolsView: View {
    let category: ToolCategory
    let events: [Event]
    let isExpanded: Bool
    let onToggle: () -> Void

    public init(
        category: ToolCategory, events: [Event],
        isExpanded: Bool, onToggle: @escaping () -> Void
    ) {
        self.category = category
        self.events = events
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: Self.categorySymbol(category))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Self.categoryTint(category))
                    .frame(width: 16, alignment: .center)

                Text("\(Self.categoryLabel(category)) × \(events.count)")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.primary)
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
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(events, id: \.id) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").font(.caption2).foregroundStyle(.tertiary)
                            Text(e.summary)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 6)
            }
        }
        .background(
            Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 4)
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - category → symbol / tint / label

    private static func categorySymbol(_ cat: ToolCategory) -> String {
        switch cat {
        case .shell:       return "terminal"
        case .fileRead:    return "doc.text"
        case .fileWrite:   return "square.and.pencil"
        case .fileSearch:  return "magnifyingglass"
        case .webFetch:    return "globe"
        case .mcpCall:     return "puzzlepiece.extension"
        case .subagent:    return "person.2"
        case .todo:        return "checklist"
        case .planMgmt:    return "list.bullet.rectangle"
        case .askUser:     return "questionmark.circle"
        case .ide:         return "keyboard"
        case .other:       return "wrench.and.screwdriver"
        default:           return "wrench.and.screwdriver"
        }
    }

    private static func categoryTint(_ cat: ToolCategory) -> Color {
        switch cat {
        case .fileRead, .fileSearch: return .blue
        case .fileWrite:             return .orange
        case .webFetch:              return .purple
        case .mcpCall:               return .teal
        case .subagent:              return .pink
        case .todo:                  return .yellow
        case .askUser:               return .orange
        default:                     return .secondary
        }
    }

    private static func categoryLabel(_ cat: ToolCategory) -> String {
        switch cat {
        case .shell:       return "Bash"
        case .fileRead:    return "Read"
        case .fileWrite:   return "Write"
        case .fileSearch:  return "Search"
        case .webFetch:    return "WebFetch"
        case .mcpCall:     return "MCP"
        case .subagent:    return "Subagent"
        case .todo:        return "Todo"
        case .planMgmt:    return "Plan"
        case .askUser:     return "AskUser"
        case .ide:         return "IDE"
        case .other:       return "Tool"
        default:           return cat.rawValue
        }
    }
}
