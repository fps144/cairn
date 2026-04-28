import XCTest
import CairnCore
import CairnStorage
@testable import CairnClaude

/// spec §8.5 M2.3 硬指标:1000 行 < 500ms。本地 M 系列 macOS 应宽松通过。
final class EventIngestorPerfTests: XCTestCase {
    private var rootURL: URL!
    private var db: CairnDatabase!
    private let defaultWsId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ing-perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        db = try await CairnDatabase(
            location: .inMemory, migrator: CairnStorage.makeMigrator()
        )
        try await WorkspaceDAO.upsert(
            Workspace(id: defaultWsId, name: "Default", cwd: "/tmp"), in: db
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func test_1000Lines_underFiveHundredMs() async throws {
        // 构造 1000 行 user_message fixture(最简单的 case,parser 开销最低)
        let lines = (0..<1000).map { i in
            #"{"type":"user","message":{"role":"user","content":"msg \#(i)"},"parentUuid":"p","timestamp":"2024-01-01T00:00:00Z","uuid":"u\#(i)"}"#
        }
        let sessionId = UUID()
        let sessionDir = rootURL.appendingPathComponent("-tmp-x")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent(sessionId.uuidString + ".jsonl")
        FileManager.default.createFile(
            atPath: jsonl.path,
            contents: Data((lines.joined(separator: "\n") + "\n").utf8)
        )

        let watcher = JSONLWatcher(database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId)
        let ingestor = EventIngestor(database: db, watcher: watcher)
        let stream = await ingestor.events()
        await ingestor.start()

        let start = DispatchTime.now()
        try await watcher.start()

        // 收齐 1000 个 persisted 事件
        var count = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await ev in stream {
                    if case .persisted = ev {
                        count += 1
                        if count >= 1000 { return }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw CancellationError()
            }
            try await group.next()
            group.cancelAll()
        }

        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        print("[M2.3 perf] 1000 lines ingested in \(String(format: "%.1f", elapsedMs))ms")

        await ingestor.stop()
        await watcher.stop()

        XCTAssertEqual(count, 1000)
        XCTAssertLessThan(elapsedMs, 500,
                          "1000 行 ingest \(elapsedMs)ms,超 500ms 上限(spec §8.5)")
    }
}
