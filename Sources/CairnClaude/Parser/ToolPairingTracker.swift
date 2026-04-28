import Foundation
import CairnCore

/// tool_use ↔ tool_result 的 in-memory 配对表。
///
/// **M2.3 改 actor → class**:需要在 `db.writeSync { ... }` 的 sync 闭包内
/// 同步调 `observe`,单事务完成 upsert → observe → updatePaired → updateCursor。
/// actor 的方法从外部角度是 async,在 sync 闭包里没法 await。
/// EventIngestor actor 内 serial 使用,NSLock 做防御性线程保护。
public final class ToolPairingTracker: @unchecked Sendable {
    private var inflight: [String: UUID] = [:]  // toolUseId → tool_use Event.id
    private let lock = NSLock()

    public init() {}

    /// 处理一批 Event:tool_use 入 inflight;tool_result 出 inflight + 填 pairedEventId。
    /// 返回修正后的 Event 数组(tool_result 的 pairedEventId 已填)。
    ///
    /// ⚠️ caller 必须先做 DB upsert 把 Event.id 替换成 stable 值再调 observe,
    /// 否则 inflight 存的是 parser 的随机 UUID,DB 里 paired_event_id 指向不存在的 id。
    public func observe(_ events: [Event]) -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        return events.map { event in
            switch event.type {
            case .toolUse:
                if let tid = event.toolUseId {
                    inflight[tid] = event.id
                }
                return event
            case .toolResult:
                guard let tid = event.toolUseId,
                      let useId = inflight.removeValue(forKey: tid) else {
                    return event
                }
                return event.withPairedEventId(useId)
            default:
                return event
            }
        }
    }

    /// 重建 inflight:从已 persisted 的 Event 列表找未配对的 tool_use。
    ///
    /// **M2.3 修订**:只把 `paired_event_id 非空` 的 tool_result 视为"已配对"。
    /// crash-recovery 下 DB 里 paired=null 的孤儿 tool_result 不应让对应
    /// tool_use 漏进 inflight —— 否则下次同 toolUseId 的 tool_result 找不到
    /// inflight 配不上。M2.2 里的 restore 没区分,M2.3 起严格要求 paired 非空。
    public func restore(from existing: [Event]) {
        lock.lock()
        defer { lock.unlock() }
        inflight.removeAll()
        var useEvents: [String: UUID] = [:]
        var pairedResultUseIds: Set<String> = []
        for e in existing {
            guard let tid = e.toolUseId else { continue }
            switch e.type {
            case .toolUse:
                useEvents[tid] = e.id
            case .toolResult:
                if e.pairedEventId != nil {
                    pairedResultUseIds.insert(tid)
                }
            default:
                break
            }
        }
        for (tid, useId) in useEvents where !pairedResultUseIds.contains(tid) {
            inflight[tid] = useId
        }
    }

    public func inflightCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return inflight.count
    }
}
