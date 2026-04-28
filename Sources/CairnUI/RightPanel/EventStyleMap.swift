import SwiftUI
import CairnCore

/// spec §6.4 Event Timeline 视觉语言 — SF Symbol 图标 + 语义色。
///
/// M2.4 T12 反馈修订:
/// - 原 emoji 图标样式不统一、占用字体系统,macOS 上色彩风格和系统 UI 脱节。
/// - 换 SF Symbols(macOS 原生、免费、Dark/Light 自动适应、风格统一)。
/// - 颜色用 semantic system colors(`.blue/.red/...`),不硬编码 hex。
/// - icon 着色(tint),summary 用 `.primary`,时间戳 `.tertiary`,层级清晰。
enum EventStyleMap {
    /// 返回 SF Symbol 名字。`Image(systemName:)` 用。
    static func symbol(for event: Event) -> String {
        if event.type == .toolUse, let cat = event.category {
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
        switch event.type {
        case .userMessage:       return "person.fill"
        case .assistantText:     return "bubble.left.fill"
        case .assistantThinking: return "brain"
        case .toolUse:           return "wrench.and.screwdriver"
        case .toolResult:        return "arrow.uturn.backward"
        case .apiUsage:          return "gauge.medium"
        case .compactBoundary:   return "arrow.triangle.merge"
        case .error:             return "exclamationmark.triangle.fill"
        case .planUpdated:       return "list.bullet.rectangle"
        case .sessionBoundary:   return "arrow.triangle.2.circlepath"
        case .approvalRequested, .approvalDecided: return "lock.shield"
        }
    }

    /// icon tint。克制:只有语义强的 event 才上彩色(错误红 / 写入橙 / 网络紫),
    /// 其余 `.secondary`,让 summary 的 `.primary` 是主角。
    static func tint(for event: Event) -> Color {
        if event.type == .toolUse, let cat = event.category {
            switch cat {
            case .fileRead, .fileSearch: return .blue
            case .fileWrite:             return .orange
            case .webFetch:              return .purple
            case .mcpCall:               return .teal
            case .subagent:              return .pink
            case .todo:                  return .yellow
            case .askUser:               return .orange
            case .shell:                 return .secondary
            default:                     return .secondary
            }
        }
        switch event.type {
        case .userMessage:       return .accentColor
        case .assistantText:     return .secondary
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
