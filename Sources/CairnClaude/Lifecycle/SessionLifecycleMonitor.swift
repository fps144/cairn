import Foundation
import GRDB
import CairnCore
import CairnStorage

/// Session 生命周期状态机(spec §4.5):
/// - `.live`      文件 mtime < 60s
/// - `.idle`      mtime 60s – 5min
/// - `.ended`     mtime ≥ 5min 且**无悬挂 tool_use**(M0.1 修订)
/// - `.abandoned` mtime ≥ 30min 且含**未配对悬挂 tool_use**
/// - `.crashed`   文件被删除(通过 watcher.removed 事件 → markCrashed)
///
/// 每 interval 秒 tick 扫活跃 sessions,按启发式计算 state,写回 DB,发 AsyncStream。
public actor SessionLifecycleMonitor {
    public struct StateChange: Sendable {
        public let sessionId: UUID
        public let oldState: SessionState?
        public let newState: SessionState
        public let timestamp: Date
    }

    private let database: CairnDatabase
    private let interval: Duration
    private var continuations: [AsyncStream<StateChange>.Continuation] = []
    private var task: Task<Void, Never>?

    public init(database: CairnDatabase, interval: Duration = .seconds(30)) {
        self.database = database
        self.interval = interval
    }

    public func events() -> AsyncStream<StateChange> {
        let (stream, cont) = AsyncStream.makeStream(of: StateChange.self)
        continuations.append(cont)
        return stream
    }

    public func start() async {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                try? await Task.sleep(for: await self.interval)
                if Task.isCancelled { return }
                await self.tick()
            }
        }
    }

    public func stop() async {
        task?.cancel()
        task = nil
        for c in continuations { c.finish() }
        continuations.removeAll()
    }

    /// 外部调:watcher.removed 事件来时立即标 `.crashed`。
    public func markCrashed(sessionId: UUID) async {
        await transition(sessionId: sessionId, to: .crashed)
    }

    // MARK: - 内部

    func tick() async {
        do {
            let activeSessions = try await SessionDAO.fetchActive(in: database)
            for s in activeSessions {
                let newState = computeState(for: s)
                if newState != s.state {
                    await transition(sessionId: s.id, from: s.state, to: newState)
                }
            }
        } catch {
            FileHandle.standardError.write(Data(
                "[LifecycleMonitor] tick failed: \(error)\n".utf8
            ))
        }
    }

    func computeState(for session: Session) -> SessionState {
        let url = URL(fileURLWithPath: session.jsonlPath)
        if !FileManager.default.fileExists(atPath: url.path) {
            return .crashed
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date) ?? session.startedAt
        let age = Date().timeIntervalSince(mtime)

        if age < 60 { return .live }
        if age < 5 * 60 { return .idle }

        let hanging = (try? countHangingToolUses(sessionId: session.id)) ?? 0
        if hanging == 0 { return .ended }
        if age >= 30 * 60 { return .abandoned }
        return .idle
    }

    private func countHangingToolUses(sessionId: UUID) throws -> Int {
        try database.readSync { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) FROM events
                WHERE session_id = ? AND type = 'tool_use'
                  AND NOT EXISTS (
                    SELECT 1 FROM events r
                    WHERE r.tool_use_id = events.tool_use_id
                      AND r.type = 'tool_result'
                  )
                """, arguments: [sessionId.uuidString])
            return row?[0] ?? 0
        }
    }

    private func transition(
        sessionId: UUID, from old: SessionState? = nil, to new: SessionState
    ) async {
        do {
            try await SessionDAO.updateState(
                sessionId: sessionId, state: new, in: database
            )
            let change = StateChange(
                sessionId: sessionId, oldState: old,
                newState: new, timestamp: Date()
            )
            for c in continuations { c.yield(change) }
        } catch {
            FileHandle.standardError.write(Data(
                "[LifecycleMonitor] transition failed: \(error)\n".utf8
            ))
        }
    }
}
