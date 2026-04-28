import Foundation
import CairnCore
import CairnStorage

/// Claude Code JSONL watcher。spec §4.2 三层兜底总入口。
///
/// 对外用 `events()` 订阅 `AsyncStream<WatcherEvent>`;必须在 `start()`
/// 之前调用以免漏 `.discovered` 初始事件。`start()` 内部:
///  ① 扫 projectsRoot 所有现有 .jsonl,建 session row,emit `.discovered`
///  ② 挂 FSEventsWatcher(目录树变化)
///  ③ 启 30s Reconciler 定时兜底
///  对每个已知 session 挂 VnodeWatcher(per-file 触发)
///
/// 本 milestone **不解析 JSONL 内容**,只 yield raw 行。parser/event-ingestor 是 M2.2/M2.3。
public actor JSONLWatcher {
    public enum WatcherEvent: Sendable {
        case discovered(Session)
        case lines(sessionId: UUID, lines: [String], lineNumberStart: Int64)
        case removed(sessionId: UUID)
    }

    private let database: CairnDatabase
    private let projectsRoot: URL
    private let defaultWorkspaceId: UUID
    private let registry = SessionRegistry()
    private var fsWatcher: FSEventsWatcher?
    private var vnodeWatchers: [UUID: VnodeWatcher] = [:]
    private var reconciler: Reconciler?
    private var continuations: [AsyncStream<WatcherEvent>.Continuation] = []
    private var backgroundTasks: [Task<Void, Never>] = []

    public init(
        database: CairnDatabase,
        projectsRoot: URL,
        defaultWorkspaceId: UUID
    ) {
        self.database = database
        self.projectsRoot = projectsRoot
        self.defaultWorkspaceId = defaultWorkspaceId
    }

    /// 多订阅者:每次调用返回独立 AsyncStream。事件 fanout 到所有活跃 continuation。
    /// **必须在 `start()` 之前调用**,否则会漏掉 start() 期间的 `scanExisting`
    /// 产生的 `.discovered` 事件。
    public func events() -> AsyncStream<WatcherEvent> {
        let (stream, cont) = AsyncStream.makeStream(of: WatcherEvent.self)
        continuations.append(cont)
        return stream
    }

    public func start() async throws {
        // 1. 初始扫描已存在文件
        let existing = try scanExisting()
        for url in existing {
            try await discover(jsonlURL: url)
        }

        // 2. 挂 FSEvents
        let fs = try FSEventsWatcher(rootURL: projectsRoot)
        self.fsWatcher = fs
        let fsStream = fs.events()
        try fs.start()
        let fsTask = Task { [weak self] in
            for await ev in fsStream {
                await self?.handleFSEvent(ev)
            }
        }
        backgroundTasks.append(fsTask)

        // 3. Reconciler
        let rec = Reconciler(interval: .seconds(30)) { [weak self] in
            await self?.runReconcile()
        }
        self.reconciler = rec
        await rec.start()
    }

    public func stop() async {
        for task in backgroundTasks { task.cancel() }
        backgroundTasks.removeAll()
        await reconciler?.stop()
        fsWatcher?.stop()
        for (_, v) in vnodeWatchers { v.stop() }
        vnodeWatchers.removeAll()
        for cont in continuations { cont.finish() }
        continuations.removeAll()
    }

    // MARK: - 内部

    private func emit(_ event: WatcherEvent) {
        for cont in continuations { cont.yield(event) }
    }

    private func scanExisting() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: projectsRoot.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            urls.append(url)
        }
        return urls
    }

    private func discover(jsonlURL: URL) async throws {
        if await registry.lookup(path: jsonlURL.path) != nil { return }

        let wsId = defaultWorkspaceId
        let basename = jsonlURL.deletingPathExtension().lastPathComponent
        let sessionId = UUID(uuidString: basename) ?? UUID()

        // ⚠️ 必须先 fetch:如果 DB 里已有这个 session 的 row(上次运行留下的),
        // 直接复用其 byte_offset / last_line_number。否则每次启动 discover
        // 都 upsert 一个全新的 session(byteOffset=0)会 ON CONFLICT DO UPDATE
        // 把已保存的 cursor 覆盖为 0,整个持久化失效。
        let session: Session
        if let existing = try await SessionDAO.fetch(id: sessionId, in: database) {
            session = existing
        } else {
            let fresh = Session(
                id: sessionId,
                workspaceId: wsId,
                jsonlPath: jsonlURL.path,
                startedAt: Date(),
                byteOffset: 0,
                lastLineNumber: 0,
                state: .live
            )
            try await SessionDAO.upsert(fresh, in: database)
            session = fresh
        }
        await registry.register(session)

        // 挂 vnode
        let v = try VnodeWatcher(fileURL: jsonlURL)
        vnodeWatchers[sessionId] = v
        let vStream = v.events()
        let vTask = Task { [weak self] in
            for await ev in vStream {
                await self?.handleVnode(sessionId: sessionId, event: ev)
            }
        }
        backgroundTasks.append(vTask)

        emit(.discovered(session))
    }

    private func handleFSEvent(_ event: FSEventsWatcher.FSEvent) async {
        switch event {
        case .created(let url):
            try? await discover(jsonlURL: url)
        case .removed(let url):
            if let session = await registry.lookup(path: url.path) {
                vnodeWatchers[session.id]?.stop()
                vnodeWatchers.removeValue(forKey: session.id)
                await registry.unregister(sessionId: session.id)
                emit(.removed(sessionId: session.id))
            }
        case .renamed:
            break  // FSEventsWatcher 已在 rename 时按 path 存在性映射到 .created / .removed
        }
    }

    private func handleVnode(sessionId: UUID, event: VnodeWatcher.VnodeEvent) async {
        switch event {
        case .write, .extend:
            await ingestNewBytes(sessionId: sessionId)
        case .delete, .rename:
            await registry.unregister(sessionId: sessionId)
            vnodeWatchers[sessionId]?.stop()
            vnodeWatchers.removeValue(forKey: sessionId)
            emit(.removed(sessionId: sessionId))
        }
    }

    private func ingestNewBytes(sessionId: UUID) async {
        guard let session = await registry.get(sessionId: sessionId) else { return }
        let url = URL(fileURLWithPath: session.jsonlPath)
        do {
            let result = try IncrementalReader.read(
                fileURL: url,
                fromOffset: session.byteOffset,
                maxBytes: 1 << 20
            )
            guard result.linesRead > 0 else { return }
            await registry.advance(
                sessionId: sessionId,
                newOffset: result.newOffset,
                linesRead: result.linesRead
            )
            try await SessionDAO.updateCursor(
                sessionId: sessionId,
                byteOffset: result.newOffset,
                lastLineNumber: session.lastLineNumber + result.linesRead,
                in: database
            )
            emit(.lines(
                sessionId: sessionId,
                lines: result.lines,
                lineNumberStart: session.lastLineNumber + 1
            ))
        } catch {
            FileHandle.standardError.write(Data(
                "[JSONLWatcher] ingest failed for \(sessionId): \(error)\n".utf8
            ))
        }
    }

    private func runReconcile() async {
        for session in await registry.all() {
            let url = URL(fileURLWithPath: session.jsonlPath)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            if size > session.byteOffset {
                await ingestNewBytes(sessionId: session.id)
            }
        }
    }
}
