import Foundation
import Observation
import CairnCore
import CairnClaude

/// 右侧 Inspector 的 Event Timeline ViewModel。
///
/// 订阅 `EventIngestor.events()` AsyncStream,在 MainActor 上维护:
/// - `currentSessionId`:M2.4 简化 — 第一个到达的 `.persisted`/`.restored` 的 sessionId
///   即为 current;后续同 session 事件追加,其他 session 事件忽略
/// - `events`:当前 session 的时间序列事件列表(按 (lineNumber, blockIndex) 排序)
///
/// M2.6 Tab↔Session 绑定后,`currentSessionId` 会由外部显式 set(用户切 tab)。
@Observable
@MainActor
public final class TimelineViewModel {
    public private(set) var currentSessionId: UUID?
    public private(set) var events: [Event] = []

    private let ingestor: EventIngestor
    private var task: Task<Void, Never>?
    /// 已入 events 数组的 id 集合,防御重复 emit。M2.3 DB 层 UNIQUE 约束已去重,
    /// UI 再加一层防御(seenIds 单增长,一个 session 几千 UUID 内存可接受)。
    private var seenIds: Set<UUID> = []

    public init(ingestor: EventIngestor) {
        self.ingestor = ingestor
    }

    /// 启动订阅。**调用方必须在 ingestor.start() 之前 await 此方法**,
    /// 否则漏 `.restored` 初始事件。
    public func start() async {
        guard task == nil else { return }
        let stream = await ingestor.events()
        task = Task { @MainActor [weak self] in
            for await ev in stream {
                self?.handle(ev)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func handle(_ ev: EventIngestor.IngestEvent) {
        switch ev {
        case .persisted(let e):
            if currentSessionId == nil {
                currentSessionId = e.sessionId
                events = []
                seenIds = []
            }
            guard e.sessionId == currentSessionId else { return }
            guard !seenIds.contains(e.id) else { return }
            seenIds.insert(e.id)
            events.append(e)

        case .restored(let sid, let restoredEvents):
            // restored 也可设定 current —— handleDiscovered 可能先 emit restored 再 persisted
            if currentSessionId == nil {
                currentSessionId = sid
            }
            guard sid == currentSessionId else { return }
            // 历史 events 按 (lineNumber, blockIndex) 排序,prepend
            let sorted = restoredEvents.sorted {
                ($0.lineNumber, $0.blockIndex) < ($1.lineNumber, $1.blockIndex)
            }
            let newOnes = sorted.filter { !seenIds.contains($0.id) }
            for e in newOnes { seenIds.insert(e.id) }
            events = newOnes + events

        case .error:
            break  // M2.4 不在 UI 显示 ingest 错误;stderr 已 log
        }
    }
}

// MARK: - Testing

extension TimelineViewModel {
    /// 测试 hook:`@testable import CairnServices` 下可见。直接 inject IngestEvent,
    /// 绕过 ingestor.events() 订阅,纯测 VM state machine。
    internal func handleForTesting(_ ev: EventIngestor.IngestEvent) {
        handle(ev)
    }
}
