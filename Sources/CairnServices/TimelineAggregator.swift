import Foundation
import CairnCore

/// 把扁平的 `[Event]` 聚合成 `[TimelineEntry]`。纯函数无状态。
///
/// 规则(spec §6.4):
/// - 连续 N ≥ 2 个**同 category** tool_use(中间允许夹着 api_usage / tool_result
///   / assistant_thinking 等"透明事件")合并为 `.mergedTools`;被合并组内的
///   tool_result 被 consume 不独立渲染,但 api_usage / 其他事件仍独立渲染
/// - 未被合并的单个 tool_use + 同 toolUseId 的 tool_result 配对为 `.toolCard`
/// - `compact_boundary` 独立 `.compactBoundary`
/// - `.assistantThinking` 且 summary 为空 → **过滤**(Claude extended thinking
///   常只留 signature,明文字段空,UI 显示无意义)
/// - 其他事件独立 `.single`
///
/// 算法:两次扫
/// 1. 扫出所有合并 group(anchor = 组第一个 tool_use.id)
/// 2. 线性生成 entries,group 只在 anchor 处 emit,其他成员跳过
public enum TimelineAggregator {
    public static func aggregate(events: [Event]) -> [TimelineEntry] {
        // 预索引:tool_use_id → tool_result
        var resultByUseId: [String: Event] = [:]
        for e in events where e.type == .toolResult {
            if let tid = e.toolUseId { resultByUseId[tid] = e }
        }

        // 第一次扫:识别合并 group
        // groupMemberEventIds:所有被合并的 tool_use.id
        // anchorToGroup:anchor tool_use.id → group 的 tool_use events
        var groupMemberEventIds: Set<UUID> = []
        var anchorToGroup: [UUID: [Event]] = [:]
        var visitedToolUseIds: Set<UUID> = []

        for i in 0..<events.count {
            let e = events[i]
            guard e.type == .toolUse,
                  !visitedToolUseIds.contains(e.id),
                  let currentCat = e.category else { continue }

            var runGroup: [Event] = [e]
            visitedToolUseIds.insert(e.id)
            var j = i + 1
            while j < events.count {
                let next = events[j]
                // "透明事件":跳过继续找同 cat tool_use
                if next.type == .apiUsage
                    || next.type == .toolResult
                    || next.type == .assistantThinking {
                    j += 1
                    continue
                }
                // 同 cat tool_use → 加入 runGroup
                if next.type == .toolUse, next.category == currentCat {
                    runGroup.append(next)
                    visitedToolUseIds.insert(next.id)
                    j += 1
                    continue
                }
                break
            }

            if runGroup.count >= 2 {
                for use in runGroup { groupMemberEventIds.insert(use.id) }
                anchorToGroup[e.id] = runGroup
            }
        }

        // 第二次扫:生成 entries
        var entries: [TimelineEntry] = []
        var consumedResultIds: Set<UUID> = []

        for e in events {
            // 已被 consume 的 tool_result 跳过
            if e.type == .toolResult && consumedResultIds.contains(e.id) {
                continue
            }

            // 被合并的 tool_use:只在 anchor 处 emit merged
            if e.type == .toolUse && groupMemberEventIds.contains(e.id) {
                if let group = anchorToGroup[e.id], let cat = e.category {
                    for use in group {
                        if let tid = use.toolUseId, let r = resultByUseId[tid] {
                            consumedResultIds.insert(r.id)
                        }
                    }
                    entries.append(.mergedTools(category: cat, events: group))
                }
                continue  // 非 anchor 成员直接跳过
            }

            switch e.type {
            case .compactBoundary:
                entries.append(.compactBoundary(e))

            case .assistantThinking:
                // 过滤空 thinking(signature-only)
                let trimmed = e.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    entries.append(.single(e))
                }

            case .toolUse:
                // 未被合并的 tool_use → toolCard(配对 or in-flight)
                let result = e.toolUseId.flatMap { resultByUseId[$0] }
                if let r = result { consumedResultIds.insert(r.id) }
                entries.append(.toolCard(toolUse: e, toolResult: result))

            default:
                entries.append(.single(e))
            }
        }
        return entries
    }
}
