# M2.3 实施计划:EventIngestor + Schema v2 migration + 批量事务

> **For agentic workers:** 本 plan 给 Claude 主导执行。用户 T13 做最终肉眼验收(跑真实 Claude session,看 events 表行数 + 配对正确性)。步骤用 checkbox 跟踪。

**Goal:** 把 M2.1 watcher 发出的 `AsyncStream<WatcherEvent>` + M2.2 parser 产的 `[Event]` + ToolPairingTracker 配对,**端到端**地写进 SQLite `events` 表。单事务批量 upsert,cursor 推进,压力测试 1000 行 < 500ms。**不做**:UI(M2.4)、工具卡片(M2.5)、session 生命周期(M2.6)。

**Architecture:**
- Schema v2 migration:`events` 加 `UNIQUE(session_id, line_number, block_index)`(M1.2 v1 只有 INDEX,upsert 没法按复合键冲突)
- `EventDAO` 改 `upsert` 语义:`ON CONFLICT(session_id, line_number, block_index) DO UPDATE SET <其他字段> = excluded.<字段>` 但 `id` 保留旧值(用 `INSERT ... RETURNING id` 拿回)→ 解决 M2.2 遗留"parser 生成的 UUID 每次不同"问题
- `EventIngestor`:CairnClaude 新增 actor,订阅 watcher stream,编排 parser + tracker + DAO 三者
- Ingest 流程单事务:一批 lines 一次 `db.write { ... }`,原子性保证
- cursor 推进:ingestor 在事务内同步调 `SessionDAO.updateCursor`(已有 sync 版本?若无则加)

本 milestone 之后 M2.4 只需要订阅 `eventIngestor.stream: AsyncStream<Event>`(已落盘后的 Event)就能驱动 Timeline。

**Tech Stack:**
- GRDB `RETURNING id` 拿回 conflict 合并后的 row id
- SQLite v3.35+(macOS 14 默认 3.39+,OK)
- Swift Concurrency `actor` + `Task` 编排

**Claude 耗时**:约 180-240 分钟。
**用户耗时**:约 15 分钟(T13 跑真实 Claude 会话 + 查 events 表)。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. Schema v2 migration:events 加 UNIQUE(sid, line, block) + migrator 注册 | Claude | — |
| T2. EventDAO `upsertByLineBlock`(ON CONFLICT 复合键,RETURNING id) | Claude | T1 |
| T3. `SessionDAO.updateCursorSync`(如果不存在)| Claude | — |
| T4. `EventIngestor` actor 骨架 + start/stop + AsyncStream 对外 | Claude | T2,T3 |
| T5. Ingestor 处理 `.discovered` 事件(tracker restore + emit 既有 events) | Claude | T4 |
| T6. Ingestor 处理 `.lines` 事件(parse → upsert → observe → updatePaired → updateCursor 单事务) | Claude | T4,T5 |
| T7. Ingestor 处理 `.removed` 事件(tracker 清理,cursor 保持) | Claude | T4 |
| T8. EventDAO.updatePairedEventId(tool_result 配对回填) | Claude | T1 |
| T9. `EventIngestorTests` 集成测试(5+):端到端 tmp JSONL → events 表 | Claude | T4-T8 |
| T10. 性能压测:1000 行 append,事务 < 500ms(spec §8.5 硬指标) | Claude | T4-T8 |
| T11. 改 CAIRN_DEV_WATCH=1 harness 用 EventIngestor 代替裸 watcher,打印 events 入库计数 | Claude | T4 |
| T12. scaffold bump `0.7.0-m2.2` → `0.8.0-m2.3` | Claude | — |
| T13. 全测试 + 真实 Claude session 触发 + 验收 | Claude | T1-T12 |
| T14. 用户验收 | **用户** | T13 |

---

## 文件结构规划

**新建**:

```
Sources/CairnStorage/Schema/
└── SchemaV2.swift                      (T1 migration 定义)

Sources/CairnClaude/Ingestor/
└── EventIngestor.swift                 (T4-T7 actor)

Tests/CairnClaudeTests/Ingestor/
├── EventIngestorTests.swift            (T9 集成 5+ 测试)
└── EventIngestorPerfTests.swift        (T10 1000 行压测)
```

**修改**:
- `Sources/CairnStorage/Schema/Migrator.swift`(注册 v2;文件名待确认)
- `Sources/CairnStorage/DAOs/EventDAO.swift`(T2 upsertByLineBlock)
- `Sources/CairnStorage/DAOs/EventDAO.swift`(T8 updatePairedEventId)
- `Sources/CairnStorage/DAOs/SessionDAO.swift`(T3 加 updateCursorSync 若无)
- `Sources/CairnApp/CairnApp.swift`(T11 harness 改)
- `Sources/CairnCore/CairnCore.swift`(T12 bump)
- 测试 scaffold 断言

---

## 设计决策(pinned)

| # | 决策 | 理由 |
|---|---|---|
| 1 | **Schema v2 加 UNIQUE(session_id, line_number, block_index)** | M2.2 遗留:parser 每次生成新 UUID,需要复合键冲突 upsert 换回 stable id |
| 2 | 用 `INSERT ... ON CONFLICT(...) DO UPDATE ... RETURNING id` | SQLite 3.35+ 支持,GRDB 7.x 直通;一句 SQL 完成 upsert + 返回 stable id |
| 3 | `EventDAO.upsertByLineBlock` 返回 DB stable id,caller 用它覆盖 `Event.id` | 配合 M2.2 tracker.observe 的 id 稳定性约束 |
| 4 | **单事务批量**:一批 lines 一次 `db.writeSync { ... }`,包含:所有 event upsert + cursor update | 原子性:崩溃要么全 commit 要么全 rollback,避免半写 |
| 5 | 批大小 = watcher 发过来的一个 `.lines` event(通常一次 vnode 触发读到的行)| 动态,无固定 chunk;大文件 IncrementalReader 按 1MB 分,自然分批 |
| 6 | cursor 用同步 write(`SessionDAO.updateCursorSync`) | M1.5 / M2.1 已有 async/sync 双版本;事务内必须同步,不能 await |
| 7 | `.discovered` 触发 tracker restore:查 DB 该 session 已有 events → `tracker.restore(from:)` | 跨启动配对重建;spec §4.4 "重启:从 DB 重建未配对 inflight" |
| 8 | `.discovered` 还 emit 已有 events 给下游(UI 初始加载) | M2.4 Timeline 上来就有历史;但 M2.3 不接 UI,emit 到 AsyncStream 供 M2.4 订阅 |
| 9 | `.removed` **不删 DB 里的 events**,只 tracker 清 inflight + emit 通知 | 数据保留供查阅;session state 变更是 M2.6 的事 |
| 10 | 错误处理:event upsert 失败 → 整个 batch 回滚 + stderr 打 warning + 跳过此 batch | 保持数据一致;cursor 不推进,下次 reconcile 会重试 |
| 11 | `EventIngestor.events() -> AsyncStream<IngestEvent>` 对外 | M2.4 订阅点;IngestEvent 简化三种:`.persisted(Event)` / `.restored([Event])` / `.error(Error)` |
| 12 | ingestor **不做 session state 转换** | M2.6 做 `.live/.ended/.abandoned/.crashed` 启发式判定 |
| 13 | ingestor **不接 UI** | M2.4 把 events() 流连到 Timeline View |
| 14 | 测试用 `CairnDatabase.inMemory` + tmp JSONL + 真 watcher 跑完整链路 | 端到端验证 parser/tracker/DAO 协同 |
| 15 | 性能压测用固定 fixture(M2.2 已裁剪)重复 1000 次,单事务 insert 测墙钟 < 500ms | spec §8.5 硬指标 |
| 16 | Migrator 严格 foreignKeyChecks:migration 前后 FK 都校验通过 | GRDB 默认;events.session_id 已 FK |
| 17 | Schema v2 migration **不迁移 events 表数据**(本机 events 表当前是空;生产 v0.1 Beta 之前无用户数据)| 零破坏;加 unique 约束后老行(若有)可能冲突,但当前无老行 |
| 18 | `upsertByLineBlock` 的 ON CONFLICT DO UPDATE **只更新非 id 字段** | id 是 stable,不动;其他字段(summary/category/pairedEventId 等)用 excluded 覆盖 |
| 19 | pairedEventId 的 **两步写入**:第一步 upsertByLineBlock 时 pairedEventId 可能为 nil(tool_result 还没被 tracker.observe);第二步 observe 后调 `updatePairedEventId` UPDATE 回写 | 一次 insert 原子拿 stable id + 一次 UPDATE 填配对,事务内两步完成 |
| 20 | 测试里 EventIngestor.stop() 必须等所有 pending Task 完成后再退出 | 避免 test cleanup 时 DAO 还在写 → 测试间相互污染 |

---

## 风险清单

| # | 风险 | 缓解 |
|---|---|---|
| 1 | `ON CONFLICT(...) DO UPDATE ... RETURNING id` 在 GRDB 7.x 行为 | 单元测试覆盖;GRDB 7 基于 SQLite 3.35+,支持 RETURNING |
| 2 | 单事务 500+ event insert 卡主线程 | ingestor 用 `Task.detached` 在 background 跑 DB write(GRDB 本身线程安全),主线程只订阅 AsyncStream |
| 3 | watcher.lines 太频繁时事务堆积 | actor 串行化;若性能告急,M2.7 引入 batch coalescing |
| 4 | tracker.observe 和 DAO update 之间 race(M2.2 配对逻辑要求先 upsert 拿 id 再 observe)| ingestor actor 内顺序保证:upsert → observe → updatePaired;三步同一线程 |
| 5 | discovered 时已有 events 太多,restore 一次读全部太慢 | M2.3 接受:一个 session 几千 event 就读几千,毫秒级;M2.7 再优化懒加载 |
| 6 | Schema v2 migration 失败(数据冲突 / FK 违反) | events 表当前实质是空的(M1.2 建表但 M2.3 才写);migration 执行顺滑;添加 UNIQUE 前不会触发 |
| 7 | `.discovered` 场景 events 表有 stale row(上次 ingestor crash 留下)| upsertByLineBlock 用 ON CONFLICT 覆盖;stale 会被新数据更新 |
| 8 | 压测 1000 行超时 | 本地 macOS M-series 应宽松通过;若不过,profiler 看是 JSON encode 还是 SQLite write 是瓶颈,M2.7 优化 |

---

## 对外 API 定义(T4 完成后固化)

```swift
// Sources/CairnClaude/Ingestor/EventIngestor.swift

public actor EventIngestor {
    public enum IngestEvent: Sendable {
        /// 新 ingest 的 event,已落盘(id 是 DB stable 值)
        case persisted(Event)
        /// discovered session 已有的历史 events(供 UI 初始加载)
        case restored(sessionId: UUID, events: [Event])
        /// ingest 失败,batch 已回滚
        case error(sessionId: UUID, lineNumberStart: Int64, error: Error)
    }

    public init(database: CairnDatabase, watcher: JSONLWatcher)

    /// 对外订阅点。必须先于 start() 调用。多订阅者 fanout。
    public func events() -> AsyncStream<IngestEvent>

    /// 启动:订阅 watcher.events(),内部起 Task 消费。
    public func start() async

    /// 停止:cancel 内部 Task,等它完成,flush。
    public func stop() async
}
```

M2.4 的典型用法:

```swift
let ingestor = EventIngestor(database: db, watcher: watcher)
let stream = await ingestor.events()
try await watcher.start()
await ingestor.start()

Task {
    for await ev in stream {
        switch ev {
        case .persisted(let e):     // M2.4 Timeline 增量追加
        case .restored(_, let es):  // M2.4 Timeline 批量加载历史
        case .error: break          // log
        }
    }
}
```

---

## Tasks

### Task 1: Schema v2 migration

**Files**:
- Create: `Sources/CairnStorage/Schema/SchemaV2.swift`
- Modify: `Sources/CairnStorage/Schema/SchemaMigrator.swift`(查确切文件名)

- [ ] **Step 1: 找 migrator 入口**

```bash
grep -rn "makeMigrator\|registerMigration" Sources/CairnStorage/ | head -10
```

找到 `makeMigrator()` 方法所在文件(M1.2 创建)。

- [ ] **Step 2: 实现 V2 migration**

```swift
// Sources/CairnStorage/Schema/SchemaV2.swift
import GRDB

/// Schema v2:events 表加 UNIQUE(session_id, line_number, block_index)。
///
/// 原因(M2.3):JSONLParser 是纯函数,每次 parse 同一行生成新 UUID。
/// M2.3 EventIngestor 需要按 (sid, line, block) 复合键 upsert 拿回
/// DB stable id,以便 tool_use↔result 配对的 paired_event_id 指向正确
/// 的 row id。v1 只有 INDEX 没 UNIQUE 约束,ON CONFLICT 无法按复合键触发。
enum SchemaV2 {
    static let sql: [String] = [
        // SQLite 不支持直接 ALTER TABLE 加 UNIQUE 约束,必须重建表。
        // 保守做法:建索引唯一即可(CREATE UNIQUE INDEX 不需要重建表)。
        "DROP INDEX IF EXISTS idx_events_session_seq",
        """
        CREATE UNIQUE INDEX idx_events_session_seq
        ON events(session_id, line_number, block_index)
        """,
    ]
}
```

**注**:用 UNIQUE INDEX 代替 ALTER TABLE ADD UNIQUE。SQLite 把 UNIQUE INDEX 视为 UNIQUE 约束,`ON CONFLICT` 和 `RETURNING` 都认。免重建表。

- [ ] **Step 3: 在 Migrator 注册**

```swift
// Migrator.swift 里,makeMigrator 方法内追加:
migrator.registerMigration("v2_events_unique_session_line_block") { db in
    for stmt in SchemaV2.sql {
        try db.execute(sql: stmt)
    }
}
```

- [ ] **Step 4: build + 测试 migrator**

```bash
swift test --filter CairnStorageTests 2>&1 | grep "Executed"
```
期望:现有 CairnStorage 测试全过(包括 migrator 的)。

- [ ] **Step 5: commit**

```bash
git add Sources/CairnStorage/Schema/SchemaV2.swift Sources/CairnStorage/Schema/*.swift
git commit -m "feat(storage): schema v2 — UNIQUE idx on events(sid, line, block) for ingest upsert"
```

---

### Task 2: EventDAO upsertByLineBlock

**Files**:
- Modify: `Sources/CairnStorage/DAOs/EventDAO.swift`

- [ ] **Step 1: 加新方法**

```swift
extension EventDAO {
    /// 按 (session_id, line_number, block_index) 复合键 upsert,返回 DB stable id。
    ///
    /// M2.3 EventIngestor 用:parser 生成的 Event.id 是随机 UUID,每次 parse
    /// 不同;但 events 表里同一个 (sid, line, block) 必须有稳定 id 供
    /// paired_event_id 指向。SQLite UPSERT + RETURNING 语句一步完成。
    ///
    /// - 已存在:用 excluded 字段覆盖非 id 字段,id 保持旧值
    /// - 不存在:插入 parser 的 id 作为 stable id
    /// 返回值:DB 里这行的 id(caller 用来覆盖 Event.id 再调 tracker.observe)
    public static func upsertByLineBlockSync(
        _ e: Event, db: GRDB.Database
    ) throws -> UUID {
        // 必须在一个 prepared statement 里完成 upsert + returning
        let row = try Row.fetchOne(db, sql: """
            INSERT INTO events
            (id, session_id, type, category, tool_name, tool_use_id,
             paired_event_id, timestamp, line_number, block_index,
             summary, raw_payload_json, byte_offset_in_jsonl)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id, line_number, block_index) DO UPDATE SET
                type = excluded.type,
                category = excluded.category,
                tool_name = excluded.tool_name,
                tool_use_id = excluded.tool_use_id,
                paired_event_id = excluded.paired_event_id,
                timestamp = excluded.timestamp,
                summary = excluded.summary,
                raw_payload_json = excluded.raw_payload_json,
                byte_offset_in_jsonl = excluded.byte_offset_in_jsonl
            RETURNING id
            """,
            arguments: [
                e.id.uuidString,
                e.sessionId.uuidString,
                e.type.rawValue,
                e.category?.rawValue,
                e.toolName,
                e.toolUseId,
                e.pairedEventId?.uuidString,
                ISO8601.string(from: e.timestamp),
                e.lineNumber,
                e.blockIndex,
                e.summary,
                e.rawPayloadJson,
                e.byteOffsetInJsonl,
            ]
        )!
        let idStr: String = row["id"]
        return UUID(uuidString: idStr)!
    }

    /// 批量 upsertByLineBlock(单事务)。返回每行的 stable id(按输入顺序)。
    /// **调用方必须已在 db.writeSync 事务内**(这里只提供 sync 版本,不 wrap 事务)。
    public static func upsertBatchByLineBlock(
        _ events: [Event],
        in db: CairnDatabase
    ) throws -> [UUID] {
        return try db.writeSync { db in
            var ids: [UUID] = []
            ids.reserveCapacity(events.count)
            for e in events {
                let id = try upsertByLineBlockSync(e, db: db)
                ids.append(id)
            }
            return ids
        }
    }
}
```

- [ ] **Step 2: 加单元测试**

```swift
// Tests/CairnStorageTests/EventDAOTests.swift 追加(或新建)

func test_upsertByLineBlock_returnsStableId() async throws {
    let db = try await CairnDatabase(location: .inMemory, migrator: CairnStorage.makeMigrator())
    let sid = UUID()
    try await WorkspaceDAO.upsert(Workspace(name: "W", cwd: "/tmp"), in: db)
    try await SessionDAO.upsert(Session(
        id: sid, workspaceId: try await WorkspaceDAO.fetchAll(in: db).first!.id,
        jsonlPath: "/tmp/x.jsonl", startedAt: Date(), state: .live
    ), in: db)

    let e1 = Event(sessionId: sid, type: .userMessage,
                   timestamp: Date(), lineNumber: 1, blockIndex: 0, summary: "hi")
    let ids1 = try EventDAO.upsertBatchByLineBlock([e1], in: db)
    XCTAssertEqual(ids1.count, 1)
    XCTAssertEqual(ids1[0], e1.id)  // 首次 insert,id 就是 parser 的 id

    // 第二次同 (sid, line, block) 不同 id 的 Event
    let e2 = Event(sessionId: sid, type: .userMessage,
                   timestamp: Date(), lineNumber: 1, blockIndex: 0, summary: "updated")
    let ids2 = try EventDAO.upsertBatchByLineBlock([e2], in: db)
    XCTAssertEqual(ids2[0], e1.id, "stable id 必须等于首次 insert 的 id,不是 e2.id")

    // 确认 row 的 summary 已更新
    let fetched = try await EventDAO.fetch(id: e1.id, in: db)
    XCTAssertEqual(fetched?.summary, "updated")
}
```

- [ ] **Step 3: 跑测试**

```bash
swift test --filter EventDAOTests 2>&1 | grep -E "Executed|fail"
```

- [ ] **Step 4: commit**

```bash
git add Sources/CairnStorage/DAOs/EventDAO.swift Tests/CairnStorageTests/
git commit -m "feat(storage): EventDAO.upsertByLineBlock — RETURNING id for stable composite-key upsert"
```

---

### Task 3: SessionDAO.updateCursorSync

**Files**:
- Modify: `Sources/CairnStorage/DAOs/SessionDAO.swift`

- [ ] **Step 1: 检查是否已有 sync 版本**

```bash
grep -n "updateCursor" Sources/CairnStorage/DAOs/SessionDAO.swift
```

如果只有 async,追加 sync 版本:

```swift
extension SessionDAO {
    public static func updateCursorSync(
        sessionId: UUID, byteOffset: Int64, lastLineNumber: Int64,
        db: GRDB.Database
    ) throws {
        try db.execute(sql: """
            UPDATE sessions SET byte_offset = ?, last_line_number = ?
            WHERE id = ?
            """,
            arguments: [byteOffset, lastLineNumber, sessionId.uuidString])
    }
}
```

**注**:这个 sync 版本接受 `GRDB.Database`(不是 `CairnDatabase`),给已在事务内的 caller 调。

- [ ] **Step 2: 单测**

```swift
func test_updateCursorSync_updatesRow() async throws {
    let db = try await CairnDatabase(...)
    // 插入 session
    // ...
    try await db.write { db in
        try SessionDAO.updateCursorSync(
            sessionId: sid, byteOffset: 1234, lastLineNumber: 5, db: db
        )
    }
    let s = try await SessionDAO.fetch(id: sid, in: db)
    XCTAssertEqual(s?.byteOffset, 1234)
    XCTAssertEqual(s?.lastLineNumber, 5)
}
```

- [ ] **Step 3: commit**

```bash
git add Sources/CairnStorage/DAOs/SessionDAO.swift Tests/CairnStorageTests/
git commit -m "feat(storage): SessionDAO.updateCursorSync for in-transaction cursor advance"
```

---

### Task 4: EventIngestor actor 骨架

**Files**:
- Create: `Sources/CairnClaude/Ingestor/EventIngestor.swift`

- [ ] **Step 1: 实现骨架**

```swift
// Sources/CairnClaude/Ingestor/EventIngestor.swift
import Foundation
import CairnCore
import CairnStorage

/// 把 JSONLWatcher 流转成已落盘 Event 的 actor 编排器。
///
/// 消费 `JSONLWatcher.WatcherEvent`:
/// - `.discovered(session)` → `ToolPairingTracker.restore(from: DB 已有 events)`
///    并 emit `.restored` 给下游
/// - `.lines(sid, lines, start)` → 对每行 parse → 单事务内批量 upsertByLineBlock
///    拿 stable id → 覆盖 Event.id → tracker.observe → updatePairedEventId →
///    updateCursorSync → emit `.persisted` 给下游
/// - `.removed(sid)` → 清 tracker 对该 session 的 inflight;emit 通知
public actor EventIngestor {
    public enum IngestEvent: Sendable {
        case persisted(Event)
        case restored(sessionId: UUID, events: [Event])
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

    public func events() -> AsyncStream<IngestEvent> {
        let (stream, cont) = AsyncStream.makeStream(of: IngestEvent.self)
        continuations.append(cont)
        return stream
    }

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

    // MARK: - 内部(T5-T7 实现)

    private func emit(_ event: IngestEvent) {
        for c in continuations { c.yield(event) }
    }

    private func handle(_ event: JSONLWatcher.WatcherEvent) async {
        switch event {
        case .discovered(let session):
            await handleDiscovered(session)
        case .lines(let sid, let lines, let start):
            await handleLines(sessionId: sid, lines: lines, startLineNumber: start)
        case .removed(let sid):
            await handleRemoved(sessionId: sid)
        }
    }

    // 占位:T5/T6/T7 填
    private func handleDiscovered(_ session: Session) async { }
    private func handleLines(sessionId: UUID, lines: [String], startLineNumber: Int64) async { }
    private func handleRemoved(sessionId: UUID) async { }
}
```

- [ ] **Step 2: build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 3: commit(骨架 only,行为 T5-T7 填)**

```bash
git add Sources/CairnClaude/Ingestor/EventIngestor.swift
git commit -m "feat(m2.3): EventIngestor actor skeleton — AsyncStream + start/stop"
```

---

### Task 5: handleDiscovered — tracker restore + emit .restored

**Files**:
- Modify: `Sources/CairnClaude/Ingestor/EventIngestor.swift`

- [ ] **Step 1: 实现**

```swift
private func handleDiscovered(_ session: Session) async {
    do {
        // 加载该 session 已有 events(按行号排序)
        let existing = try await EventDAO.fetch(
            sessionId: session.id, limit: 10_000, offset: 0, in: database
        )
        // 重建 tracker inflight:未配对的 tool_use 进 inflight
        await tracker.restore(from: existing)
        if !existing.isEmpty {
            emit(.restored(sessionId: session.id, events: existing))
        }
    } catch {
        emit(.error(sessionId: session.id, lineNumberStart: 0, error: error))
    }
}
```

**注**:limit 10_000 足够(典型 session 事件数百到数千)。M2.7 优化懒加载。

- [ ] **Step 2: commit**

```bash
git add Sources/CairnClaude/Ingestor/EventIngestor.swift
git commit -m "feat(m2.3): EventIngestor handleDiscovered — tracker restore + emit restored"
```

---

### Task 6: handleLines — 核心事务

**Files**:
- Modify: `Sources/CairnClaude/Ingestor/EventIngestor.swift`

- [ ] **Step 1: 实现**

```swift
private func handleLines(
    sessionId: UUID, lines: [String], startLineNumber: Int64
) async {
    // 1. parse 所有行 → [Event](可能跨多行多 block)
    var parsed: [Event] = []
    for (i, line) in lines.enumerated() {
        let lineNum = startLineNumber + Int64(i)
        // isFirstLine 在 M2.1 里已经通过 lineNumberStart 间接传递:
        // 真正的文件首行只会出现在 startLineNumber == 1 的 batch 里
        let isFirst = (lineNum == 1)
        parsed.append(contentsOf: JSONLParser.parse(
            line: line, sessionId: sessionId,
            lineNumber: lineNum, isFirstLine: isFirst
        ))
    }
    guard !parsed.isEmpty else { return }

    // 2. 单事务:upsertByLineBlock 换 stable id → observe → updatePaired → cursor
    do {
        let stableEvents = try await database.write { db in
            // 第一步:upsert 拿 stable id,覆盖 parsed 的 random UUID
            var withStableId: [Event] = []
            withStableId.reserveCapacity(parsed.count)
            for e in parsed {
                let stableId = try EventDAO.upsertByLineBlockSync(e, db: db)
                var copy = e
                copy.id = stableId  // ⚠️ Event.id 是 let,这里不能直接改
                // —— 见下方注释,Event 需要 mutating helper,或改 id 为 var
                withStableId.append(copy)
            }
            return withStableId
        }

        // 3. tracker.observe 填 pairedEventId(此时 id 已稳定)
        let paired = await tracker.observe(stableEvents)

        // 4. 再次单事务:回写 pairedEventId + 推进 cursor
        try await database.write { db in
            for e in paired where e.pairedEventId != nil {
                try EventDAO.updatePairedEventIdSync(
                    eventId: e.id, pairedEventId: e.pairedEventId,
                    db: db
                )
            }
            // 推进 cursor
            if let last = paired.last {
                try SessionDAO.updateCursorSync(
                    sessionId: sessionId,
                    byteOffset: /* 需要从哪拿?见下 */ 0,
                    lastLineNumber: last.lineNumber,
                    db: db
                )
            }
        }

        // 5. emit
        for e in paired { emit(.persisted(e)) }
    } catch {
        emit(.error(sessionId: sessionId, lineNumberStart: startLineNumber, error: error))
    }
}
```

**未解决点 1(Event.id 可变性)**:Event.id 是 `let`。要改 id 必须:
- 方案 A:Event 改 `public var id` —— 破坏不变性,但 v1 已经在 restore 等场景接受 var
- 方案 B:`Event.withId(_ newId: UUID) -> Event` 返回新 struct —— 更干净

选方案 B。在 Event.swift 加扩展(CairnCore):

```swift
// Sources/CairnCore/Event.swift 追加
extension Event {
    public func withId(_ newId: UUID) -> Event {
        return Event(
            id: newId,
            sessionId: sessionId,
            type: type,
            category: category,
            toolName: toolName,
            toolUseId: toolUseId,
            pairedEventId: pairedEventId,
            timestamp: timestamp,
            lineNumber: lineNumber,
            blockIndex: blockIndex,
            summary: summary,
            rawPayloadJson: rawPayloadJson,
            byteOffsetInJsonl: byteOffsetInJsonl
        )
    }
}
```

handleLines 里改:`let copy = e.withId(stableId)`。

**未解决点 2(byteOffset 从哪拿)**:Watcher 的 `.lines` 事件目前只给 `lines + lineNumberStart`,没给字节偏移。IncrementalReader 返回 `newOffset` 但没传到 WatcherEvent。

两种修:
- 方案 A:修改 `WatcherEvent.lines` 加 `byteOffsetAfter: Int64` 字段,watcher 内部 ingestNewBytes 把 `result.newOffset` 传过来
- 方案 B:ingestor 手动 `FileManager.attributesOfItem` 看文件 size 作为 cursor(不精确,不同步)

选方案 A。修 M2.1 的 JSONLWatcher.WatcherEvent。

### Task 6 先决依赖

Task 6 之前需要:

- [ ] **Step 0a: 给 Event 加 withId(_:)**

```swift
// Sources/CairnCore/Event.swift
extension Event {
    public func withId(_ newId: UUID) -> Event { ... }  // 见上
}
```

- [ ] **Step 0b: 修改 JSONLWatcher.WatcherEvent 加字节偏移**

```swift
// Sources/CairnClaude/Watcher/JSONLWatcher.swift
public enum WatcherEvent: Sendable {
    case discovered(Session)
    case lines(sessionId: UUID, lines: [String],
               lineNumberStart: Int64, byteOffsetAfter: Int64)  // ← 新字段
    case removed(sessionId: UUID)
}
```

ingestNewBytes 调用 emit 时传 `result.newOffset`。

**影响**:M2.1 的 `JSONLWatcherIntegrationTests` 里 lines pattern 匹配要更新。

- [ ] **Step 0c: 跑 M2.1 测试确认未坏**

```bash
swift test --filter JSONLWatcherIntegrationTests 2>&1 | grep Executed
```

- [ ] **Step 1: 回到 handleLines 完整实现**(改用 withId + byteOffsetAfter)

```swift
private func handleLines(
    sessionId: UUID, lines: [String], startLineNumber: Int64, byteOffsetAfter: Int64
) async {
    var parsed: [Event] = []
    for (i, line) in lines.enumerated() {
        let lineNum = startLineNumber + Int64(i)
        let isFirst = (lineNum == 1)
        parsed.append(contentsOf: JSONLParser.parse(
            line: line, sessionId: sessionId,
            lineNumber: lineNum, isFirstLine: isFirst
        ))
    }
    guard !parsed.isEmpty else {
        // 仍要推进 cursor(忽略类型的行也要推进,否则下次 reconcile 重读)
        try? await database.write { db in
            try SessionDAO.updateCursorSync(
                sessionId: sessionId, byteOffset: byteOffsetAfter,
                lastLineNumber: startLineNumber + Int64(lines.count) - 1, db: db
            )
        }
        return
    }

    do {
        // 事务 1:upsert + cursor
        let stableEvents = try await database.write { db -> [Event] in
            var result: [Event] = []
            result.reserveCapacity(parsed.count)
            for e in parsed {
                let stableId = try EventDAO.upsertByLineBlockSync(e, db: db)
                result.append(e.withId(stableId))
            }
            try SessionDAO.updateCursorSync(
                sessionId: sessionId,
                byteOffset: byteOffsetAfter,
                lastLineNumber: (parsed.last?.lineNumber ?? startLineNumber),
                db: db
            )
            return result
        }

        // tracker.observe:填 pairedEventId
        let paired = await tracker.observe(stableEvents)

        // 事务 2:回写 pairedEventId
        let toUpdate = paired.filter { $0.pairedEventId != nil }
        if !toUpdate.isEmpty {
            try await database.write { db in
                for e in toUpdate {
                    try EventDAO.updatePairedEventIdSync(
                        eventId: e.id, pairedEventId: e.pairedEventId,
                        db: db
                    )
                }
            }
        }

        for e in paired { emit(.persisted(e)) }
    } catch {
        emit(.error(sessionId: sessionId, lineNumberStart: startLineNumber, error: error))
    }
}
```

- [ ] **Step 2: 对应修改 watcher.ingestNewBytes 里 emit 的 args**

JSONLWatcher.ingestNewBytes 已有 `result.newOffset`,加到 emit:

```swift
emit(.lines(
    sessionId: sessionId,
    lines: result.lines,
    lineNumberStart: session.lastLineNumber + 1,
    byteOffsetAfter: result.newOffset  // ← 新字段
))
```

- [ ] **Step 3: build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 4: commit**

```bash
git add Sources/CairnCore/Event.swift Sources/CairnClaude/Watcher/JSONLWatcher.swift Sources/CairnClaude/Ingestor/EventIngestor.swift Tests/CairnClaudeTests/
git commit -m "feat(m2.3): EventIngestor handleLines — upsert stable id + observe + update cursor (single tx)"
```

---

### Task 7: handleRemoved

**Files**:
- Modify: `Sources/CairnClaude/Ingestor/EventIngestor.swift`

```swift
private func handleRemoved(sessionId: UUID) async {
    // tracker 对该 session 的 inflight 清理 —— 但 tracker 没有 per-session API
    // M2.3 简化:不清理(inflight 留着也不影响;session 的 events 一旦配对就稳定)
    // M2.6 做 session `.crashed` 判定时再清理
    // 此处 emit 一个通知给下游(M2.4 可用来移除 UI timeline)
    // M2.3 简化:不 emit,纯 no-op
    _ = sessionId
}
```

- [ ] **Step 1: 实现**(如上,空 body 注释说明范围)

- [ ] **Step 2: commit**

```bash
git add Sources/CairnClaude/Ingestor/EventIngestor.swift
git commit -m "feat(m2.3): EventIngestor handleRemoved — no-op placeholder (full handling in M2.6)"
```

---

### Task 8: EventDAO.updatePairedEventIdSync

**Files**:
- Modify: `Sources/CairnStorage/DAOs/EventDAO.swift`

```swift
extension EventDAO {
    /// 回写 tool_result 的 paired_event_id。在 upsertByLineBlock 之后、
    /// tracker.observe 填完 id 之后调用。
    public static func updatePairedEventIdSync(
        eventId: UUID, pairedEventId: UUID?, db: GRDB.Database
    ) throws {
        try db.execute(sql: """
            UPDATE events SET paired_event_id = ? WHERE id = ?
            """,
            arguments: [pairedEventId?.uuidString, eventId.uuidString])
    }
}
```

- [ ] **Step 1: 实现**
- [ ] **Step 2: 单测**

```swift
func test_updatePairedEventIdSync() async throws {
    // 插入两行:tool_use, tool_result
    // 用 updatePairedEventIdSync 关联它们
    // 读回 tool_result 的 paired_event_id 应等于 tool_use.id
}
```

- [ ] **Step 3: commit**

```bash
git add Sources/CairnStorage/DAOs/EventDAO.swift Tests/CairnStorageTests/
git commit -m "feat(storage): EventDAO.updatePairedEventIdSync for post-upsert pairing"
```

---

### Task 9: EventIngestor 集成测试

**Files**:
- Create: `Tests/CairnClaudeTests/Ingestor/EventIngestorTests.swift`

**5 个场景**:
1. `test_endToEnd_userMessage_persists`
2. `test_endToEnd_toolUse_toolResult_pairs`
3. `test_restore_rebuildsInflightFromDb`
4. `test_malformedLine_skipsBatch_noRollback`
5. `test_cursor_advances_on_ingest`

```swift
// Tests/CairnClaudeTests/Ingestor/EventIngestorTests.swift
import XCTest
import CairnCore
import CairnStorage
@testable import CairnClaude

final class EventIngestorTests: XCTestCase {
    private var rootURL: URL!
    private var db: CairnDatabase!
    private let defaultWsId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("ing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        db = try await CairnDatabase(location: .inMemory, migrator: CairnStorage.makeMigrator())
        try await WorkspaceDAO.upsert(Workspace(id: defaultWsId, name: "W", cwd: "/tmp"), in: db)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func test_endToEnd_userMessage_persists() async throws {
        // 写一个 user_message 的 JSONL
        let sessionDir = rootURL.appendingPathComponent("-tmp-x")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let sessionId = UUID()
        let jsonl = sessionDir.appendingPathComponent(sessionId.uuidString + ".jsonl")
        let line = #"{"type":"user","message":{"role":"user","content":"hello"},"parentUuid":"p1","timestamp":"2024-01-01T00:00:00Z","uuid":"e1"}"#
        try (line + "\n").write(to: jsonl, atomically: true, encoding: .utf8)

        let watcher = JSONLWatcher(database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId)
        let ingestor = EventIngestor(database: db, watcher: watcher)
        let stream = await ingestor.events()
        try await watcher.start()
        await ingestor.start()
        defer { Task { await ingestor.stop(); await watcher.stop() } }

        // 等一个 persisted
        let e = try await withTimeout(seconds: 5) { () -> Event? in
            for await ev in stream {
                if case .persisted(let e) = ev, e.type == .userMessage { return e }
            }
            return nil
        }
        XCTAssertNotNil(e)

        // DB 里应有这行
        let inDb = try await EventDAO.fetch(sessionId: e!.sessionId, limit: 100, offset: 0, in: db)
        XCTAssertTrue(inDb.contains { $0.id == e!.id })
    }

    // ... 4 更多场景

    private func withTimeout<T: Sendable>(seconds: Double, _ body: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
```

完整 5 个 test 内容按 plan 框架展开(T9 执行时补齐 tool pairing / restore / cursor / malformed 四个 case,每个 30-60 行)。

- [ ] **Step 1: 实现 5 tests**
- [ ] **Step 2: 跑**

```bash
swift test --filter EventIngestorTests 2>&1 | grep -E "Executed|fail"
```

- [ ] **Step 3: commit**

```bash
git add Tests/CairnClaudeTests/Ingestor/
git commit -m "test(m2.3): EventIngestor end-to-end integration (5 cases)"
```

---

### Task 10: 性能压测

**Files**:
- Create: `Tests/CairnClaudeTests/Ingestor/EventIngestorPerfTests.swift`

```swift
final class EventIngestorPerfTests: XCTestCase {
    func test_1000Lines_underFiveHundredMs() async throws {
        // 构造 tmp 目录 + tmp JSONL(1000 行 assistant-text)
        // 启动 watcher + ingestor
        // measure 从 start 到所有 persisted 事件收齐的耗时
        // XCTAssertLessThan(elapsedMs, 500)
    }
}
```

完整实现按 M2.2 的 smoke test 套路,手动测 end-to-end 墙钟。

- [ ] **Step 1: 实现**
- [ ] **Step 2: 跑**
- [ ] **Step 3: commit**

---

### Task 11: Harness 改用 EventIngestor

**Files**:
- Modify: `Sources/CairnApp/CairnApp.swift`

- [ ] **Step 1: initializeDatabase 末尾改**

把 M2.1 的裸 watcher 日志循环,换成 watcher + ingestor + 订阅 ingestor.events:

```swift
if ProcessInfo.processInfo.environment["CAIRN_DEV_WATCH"] == "1",
   let db = appDelegate.database {
    let root = URL(fileURLWithPath: "\(NSHomeDirectory())/.claude/projects")
    let watcher = JSONLWatcher(database: db, projectsRoot: root, defaultWorkspaceId: appDelegate.defaultWorkspaceId)
    let ingestor = EventIngestor(database: db, watcher: watcher)
    appDelegate.jsonlWatcher = watcher
    appDelegate.eventIngestor = ingestor

    let stream = await ingestor.events()
    Task {
        var persistedCount = 0
        for await ev in stream {
            switch ev {
            case .persisted: persistedCount += 1
                if persistedCount % 100 == 0 {
                    FileHandle.standardError.write(Data(
                        "[Ingestor] persisted \(persistedCount) events\n".utf8
                    ))
                }
            case .restored(let sid, let es):
                FileHandle.standardError.write(Data(
                    "[Ingestor] restored \(es.count) events for \(sid)\n".utf8
                ))
            case .error(let sid, _, let err):
                FileHandle.standardError.write(Data(
                    "[Ingestor] error on \(sid): \(err)\n".utf8
                ))
            }
        }
    }

    try? await watcher.start()
    await ingestor.start()
}
```

delegate 加字段 `var eventIngestor: EventIngestor?` + willTerminate stop 它。

- [ ] **Step 2: build**
- [ ] **Step 3: commit**

---

### Task 12: scaffold bump

`0.7.0-m2.2` → `0.8.0-m2.3`,3 处断言同步。

---

### Task 13: 最终验证

- [ ] Clean build + `swift test` 全绿(预期 160 + M2.3 新 10 = ~170)
- [ ] dev harness 真实触发:`CAIRN_DEV_WATCH=1 build/Cairn.app/Contents/MacOS/CairnApp`,检查:
  - `[Ingestor] persisted N events` 流出
  - 没 `[Ingestor] error`
  - `events` 表行数 > 0
  - tool_use 和 tool_result 的 paired_event_id 正确指向对端 id

---

### Task 14: 用户验收

```bash
# 1. 全测试
swift test 2>&1 | grep "Executed.*tests"
# 期望:~170, 0 failures

# 2. 清 events + 真实 Claude 触发
sqlite3 "/Users/sorain/Library/Application Support/Cairn/cairn.sqlite" \
  "DELETE FROM events;"
CAIRN_DEV_WATCH=1 build/Cairn.app/Contents/MacOS/CairnApp 2>&1 | tee /tmp/ing.log &
PID=$!
sleep 10
# 在另一终端:cd /tmp && claude,跟它聊几句
sleep 30
kill -TERM $PID

# 3. 磁盘取证
sqlite3 "/Users/sorain/Library/Application Support/Cairn/cairn.sqlite" \
  "SELECT type, COUNT(*) FROM events GROUP BY type;"
# 期望:user_message/assistant_text/tool_use/tool_result/api_usage 都有几个

sqlite3 "/Users/sorain/Library/Application Support/Cairn/cairn.sqlite" \
  "SELECT COUNT(*) FROM events WHERE type='tool_use';"
sqlite3 "/Users/sorain/Library/Application Support/Cairn/cairn.sqlite" \
  "SELECT COUNT(*) FROM events WHERE type='tool_result' AND paired_event_id IS NOT NULL;"
# 期望:tool_use 数量 ≈ 已配对的 tool_result 数量
```

**验收 5 项**:

| # | 检查 | 期望 |
|---|---|---|
| 1 | 全测试 | ~170, 0 failures |
| 2 | `[Ingestor] persisted N events` 日志出现 | 非 0 |
| 3 | `events` 表有行 | 跑完 Claude 后非空 |
| 4 | tool_use ≈ tool_result(已配对) | 差距 ≤ 活跃未结束的一两个 |
| 5 | paired_event_id 正确指向 tool_use 的 id | SELECT JOIN 验证对齐 |

---

## Known limitations(留给后续 milestone)

- **session state 不转换**:ingestor 不设 `.ended/.abandoned/.crashed`(M2.6)
- **UI 不接**:stream 没有消费者,仅 harness 打日志(M2.4)
- **handleRemoved 是 no-op**:M2.6 做 session 消失后的状态清理
- **restore limit 10_000**:大 session 若事件 > 10k 会截断(M2.7 懒加载)
- **两步事务**:pairedEventId 回写是独立第二事务,极端情况(崩溃在两事务之间)会留下 tool_result 没配对;下次启动 tracker.restore 从 DB 重建 inflight 修复
- **不做 session workspace 反推**:M2.6

---

## 完成定义

T1-T13 全打勾 + T14 用户 ✅ + tag `m2-3-done` + milestone-log 追 M2.3 条目。
