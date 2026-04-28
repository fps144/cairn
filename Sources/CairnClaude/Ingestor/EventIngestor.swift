import Foundation
import CairnCore
import CairnStorage

/// 把 `JSONLWatcher` 发出的流**端到端**地写进 SQLite `events` 表。
///
/// 消费 `JSONLWatcher.WatcherEvent`:
/// - `.discovered(session)` → 从 DB 加载该 session 已有 events → `ToolPairingTracker.restore`
///   重建 inflight,emit `.restored` 给下游(M2.4 Timeline 初始加载)
/// - `.lines(sid, lines, start, byteOffsetAfter)` → 对每行 parse → **单事务**:
///   ① `EventDAO.upsertByLineBlockSync` 换回 DB stable id
///   ② `tracker.observe(stableEvents)` 填 `pairedEventId`
///   ③ `EventDAO.updatePairedEventIdSync` 回写配对
///   ④ `SessionDAO.updateCursorSync` 推进 cursor
///   事务外 emit `.persisted` 给下游
/// - `.removed(sid)` → M2.3 no-op(`.crashed` 状态转换留 M2.6)
public actor EventIngestor {
    public enum IngestEvent: Sendable {
        /// 新 ingest 的 event,已落盘(id 是 DB stable 值)
        case persisted(Event)
        /// discovered session 已有的历史 events(供 UI 初始加载)
        case restored(sessionId: UUID, events: [Event])
        /// ingest 失败,batch 已回滚
        case error(sessionId: UUID, lineNumberStart: Int64, error: Error)
    }

    private let database: CairnDatabase
    private let watcher: JSONLWatcher
    private let tracker = ToolPairingTracker()
    private var continuations: [AsyncStream<IngestEvent>.Continuation] = []
    private var consumerTask: Task<Void, Never>?

    public init(database: CairnDatabase, watcher: JSONLWatcher) {
        self.database = database
        self.watcher = watcher
    }

    /// 对外订阅点。**必须先于 `start()` 调用**,否则漏 `.restored` 初始事件。
    /// 多订阅者 fanout。
    public func events() -> AsyncStream<IngestEvent> {
        let (stream, cont) = AsyncStream.makeStream(of: IngestEvent.self)
        continuations.append(cont)
        return stream
    }

    /// 启动:订阅 watcher.events(),内部起 Task 消费。
    /// **caller 必须先 `events()` 再 `start()`,然后再 `watcher.start()`**。
    public func start() async {
        guard consumerTask == nil else { return }
        let stream = await watcher.events()
        consumerTask = Task { [weak self] in
            for await event in stream {
                await self?.handle(event)
            }
        }
    }

    public func stop() async {
        consumerTask?.cancel()
        consumerTask = nil
        for c in continuations { c.finish() }
        continuations.removeAll()
    }

    // MARK: - 内部

    private func emit(_ event: IngestEvent) {
        for c in continuations { c.yield(event) }
    }

    private func handle(_ event: JSONLWatcher.WatcherEvent) async {
        switch event {
        case .discovered(let session):
            await handleDiscovered(session)
        case .lines(let sid, let lines, let start, let byteOffsetAfter):
            await handleLines(
                sessionId: sid, lines: lines,
                startLineNumber: start, byteOffsetAfter: byteOffsetAfter
            )
        case .removed(let sid):
            handleRemoved(sessionId: sid)
        }
    }

    private func handleDiscovered(_ session: Session) async {
        do {
            // 加载该 session 已有 events(按行号排序)
            let existing = try await EventDAO.fetch(
                sessionId: session.id, limit: 10_000, offset: 0, in: database
            )
            // 重建 tracker inflight(修订版:只认 paired 非空的为已配对)
            tracker.restore(from: existing)
            if !existing.isEmpty {
                emit(.restored(sessionId: session.id, events: existing))
            }
        } catch {
            emit(.error(sessionId: session.id, lineNumberStart: 0, error: error))
        }
    }

    private func handleLines(
        sessionId: UUID, lines: [String],
        startLineNumber: Int64, byteOffsetAfter: Int64
    ) async {
        // 1. parse 所有行 → [Event]
        var parsed: [Event] = []
        for (i, line) in lines.enumerated() {
            let lineNum = startLineNumber + Int64(i)
            let isFirst = (lineNum == 1)
            parsed.append(contentsOf: JSONLParser.parse(
                line: line, sessionId: sessionId,
                lineNumber: lineNum, isFirstLine: isFirst
            ))
        }

        // 2. **单事务**:upsert → observe → updatePaired → updateCursor。
        //    tracker 是 class,observe 可在 sync 闭包内直接调用。
        //    即使 parsed 为空(全是忽略类型),也要推进 cursor(否则 reconcile 重读)。
        do {
            let paired: [Event] = try database.writeSync { [tracker] db -> [Event] in
                // 2.1 upsertByLineBlock → stable id
                var withStableId: [Event] = []
                withStableId.reserveCapacity(parsed.count)
                for e in parsed {
                    let stableId = try EventDAO.upsertByLineBlockSync(e, db: db)
                    withStableId.append(e.withId(stableId))
                }
                // 2.2 tracker.observe(sync)— 填 pairedEventId
                let paired = tracker.observe(withStableId)
                // 2.3 回写 pairedEventId(只对真正配对的 tool_result)
                for e in paired where e.pairedEventId != nil {
                    try EventDAO.updatePairedEventIdSync(
                        eventId: e.id, pairedEventId: e.pairedEventId, db: db
                    )
                }
                // 2.4 推进 cursor —— 用 batch 实际最后一行的 lineNumber
                let lastLineNumber = parsed.last?.lineNumber
                    ?? (startLineNumber + Int64(lines.count) - 1)
                try SessionDAO.updateCursorSync(
                    sessionId: sessionId,
                    byteOffset: byteOffsetAfter,
                    lastLineNumber: lastLineNumber,
                    db: db
                )
                return paired
            }

            // 3. emit 在事务外,不持锁
            for e in paired { emit(.persisted(e)) }
        } catch {
            emit(.error(
                sessionId: sessionId,
                lineNumberStart: startLineNumber,
                error: error
            ))
        }
    }

    private func handleRemoved(sessionId: UUID) {
        // M2.3 范围:no-op。
        // - tracker 对该 session 的 inflight 不清理(inflight 留着也不影响;
        //   session 的 events 一旦配对就稳定)
        // - session state `.crashed` 判定 + DB 侧处理留 M2.6
        _ = sessionId
    }
}
