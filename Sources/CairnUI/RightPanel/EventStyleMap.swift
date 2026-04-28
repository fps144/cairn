import SwiftUI
import CairnCore

/// spec §6.4 Event Timeline 视觉语言 — icon / color 映射。
/// 两种入口:`EventType`(对 toolUse 之外的事件)+ `ToolCategory`(toolUse 细分)。
enum EventStyleMap {
    static func icon(for event: Event) -> String {
        if event.type == .toolUse, let cat = event.category {
            switch cat {
            case .shell:       return "🔧"
            case .fileRead:    return "📖"
            case .fileWrite:   return "✏️"
            case .fileSearch:  return "🔍"
            case .webFetch:    return "🌐"
            case .mcpCall:     return "🔌"
            case .subagent:    return "🧬"
            case .todo:        return "📋"
            case .planMgmt:    return "📐"
            case .askUser:     return "❓"
            case .ide:         return "💻"
            case .other:       return "🛠"
            default:           return "🛠"
            }
        }
        switch event.type {
        case .userMessage:       return "👤"
        case .assistantText:     return "💬"
        case .assistantThinking: return "💭"
        case .toolUse:           return "🛠"
        case .toolResult:        return "↩︎"
        case .apiUsage:          return "💰"
        case .compactBoundary:   return "───"
        case .error:             return "⚠️"
        case .planUpdated:       return "📐"
        case .sessionBoundary:   return "✴"
        case .approvalRequested, .approvalDecided: return "🔐"
        }
    }

    static func color(for event: Event) -> Color {
        if event.type == .toolUse, let cat = event.category {
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
        switch event.type {
        case .userMessage:       return .secondary
        case .assistantText:     return .primary
        case .assistantThinking: return .secondary
        case .toolUse:           return .secondary
        case .toolResult:        return .secondary
        case .apiUsage:          return .green
        case .compactBoundary:   return .secondary
        case .error:             return .red
        default:                 return .secondary
        }
    }
}
