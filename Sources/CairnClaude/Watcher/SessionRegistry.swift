import Foundation
import CairnCore

/// 活跃 session 的内存注册表。actor 保证线程安全。
public actor SessionRegistry {
    private var byId: [UUID: Session] = [:]
    private var byPath: [String: UUID] = [:]

    public init() {}

    public func register(_ session: Session) {
        byId[session.id] = session
        byPath[session.jsonlPath] = session.id
    }

    public func unregister(sessionId: UUID) {
        guard let s = byId.removeValue(forKey: sessionId) else { return }
        byPath.removeValue(forKey: s.jsonlPath)
    }

    public func advance(sessionId: UUID, newOffset: Int64, linesRead: Int64) {
        guard var s = byId[sessionId] else { return }
        s.byteOffset = newOffset
        s.lastLineNumber += linesRead
        byId[sessionId] = s
    }

    public func get(sessionId: UUID) -> Session? { byId[sessionId] }
    public func lookup(path: String) -> Session? {
        guard let sid = byPath[path] else { return nil }
        return byId[sid]
    }

    public func all() -> [Session] { Array(byId.values) }
}
