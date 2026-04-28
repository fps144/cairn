# M2.1 实施计划:JSONLWatcher(FSEvents + vnode + 30s reconcile)

> **For agentic workers:** 本 plan 给 Claude 主导执行,用户 T13 做最终肉眼验收。步骤用 checkbox 跟踪。

**Goal:** 给 Cairn 加装 Claude Code 观察能力的**最底层** — 一个能发现 `~/.claude/projects/` 下所有 session JSONL 文件、按字节偏移增量读取、永不读半行、并以 `AsyncStream<String>` 对外 yield raw JSON 行的 watcher。**不做**:JSONL → Event 映射(M2.2),批量事务写 events 表(M2.3),UI(M2.4)。本 milestone 结束时,watcher 只"发流",上游消费者留空。

**Architecture:** CairnClaude 新增 `Watcher/` 子目录,按单一职责拆成 6 个文件:

- `FSEventsWatcher`:包 `FSEventStreamCreate` C API,监听 `~/.claude/projects/` 的**目录树**变化(新文件 / 新子目录 / 删除),产 `AsyncStream<FSEvent>`
- `VnodeWatcher`:包 `DispatchSourceFileSystemObject`,per-file `.write`/`.extend` 事件,产 `AsyncStream<Void>`(触发器)
- `IncrementalReader`:按 `FileHandle.seek(toOffset:)` 读块,永远只返回**完整行**,返回推进后的 byteOffset + 行号
- `SessionRegistry`:内存里活跃 session 的 cursor 缓存 + 路径 ↔ sessionId 索引
- `Reconciler`:每 30s 对比 DB `sessions` 表 vs 磁盘文件(大小 / mtime)兜底补漏
- `JSONLWatcher`:actor 总装,对外 3 个 AsyncStream(session discovered / session line / session removed)+ `start()` / `stop()`

CairnApp 层不对接(那是 M2.6 的事)。本 milestone 末,watcher 在**独立测试 harness** 里跑:手动 `await watcher.start()`,用真实 Claude Code 跑一次,看 stderr 日志流出 discovered / line 事件。

**Tech Stack:**
- `CoreServices.FSEvents`(C API + Swift wrapper)
- Swift Concurrency:`actor` + `AsyncStream` + `Task.sleep`
- `DispatchSourceFileSystemObject`(per-file vnode)
- `FileHandle`:`seek(toOffset:)` + `read(upToCount:)`
- 已有基建:`Session` / `SessionDAO.updateCursor` / `SessionDAO.fetchActive`(M1.2 就绪)
- M0.1 probe:1620 个 system entry 验证 cwd 位置、22 hash 目录实测

**Claude 耗时**:约 180-240 分钟。
**用户耗时**:约 15 分钟(T13 含真实 Claude 触发 + 日志核对)。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. M0.1 probe + spec §4.2 要点笔记 | Claude | — |
| T2. `IncrementalReader`(纯函数:offset→(lines, newOffset)) | Claude | — |
| T3. `VnodeWatcher`(DispatchSource per file 触发器) | Claude | — |
| T4. `FSEventsWatcher`(C API wrap,目录树变化流) | Claude | — |
| T5. `SessionRegistry`(内存 cursor 管理,actor) | Claude | T2 |
| T6. `Reconciler`(30s 定时对比 DB vs 磁盘) | Claude | T5 |
| T7. `JSONLWatcher` 总装 actor + 3 个 AsyncStream | Claude | T3, T4, T5, T6 |
| T8. Path hash 反推工具 `ProjectsDirLayout`(~/.claude/projects hash 解析) | Claude | — |
| T9. 单测覆盖 T2–T8(≥ 18 个 case) | Claude | T2–T8 |
| T10. 手动集成 harness(CairnApp dev-only 开关,启动 log 流) | Claude | T7 |
| T11. scaffoldVersion bump `0.5.0-m1.5` → `0.6.0-m2.1` | Claude | — |
| T12. build + swift test + harness 真实 Claude 触发自检 | Claude | T1–T11 |
| T13. 验收清单(用户真实 Claude session 触发 + 看日志) | **用户** | T12 |

---

## 文件结构规划

**新建**:

```
Sources/CairnClaude/
├── Claude.swift                           (修:scaffoldVersion bump)
└── Watcher/
    ├── IncrementalReader.swift            (T2)
    ├── VnodeWatcher.swift                 (T3)
    ├── FSEventsWatcher.swift              (T4)
    ├── SessionRegistry.swift              (T5)
    ├── Reconciler.swift                   (T6)
    ├── JSONLWatcher.swift                 (T7 总入口)
    └── ProjectsDirLayout.swift            (T8 工具:路径 hash 规则)

Tests/CairnClaudeTests/
├── ClaudeTests.swift                      (改 scaffoldVersion 断言)
└── Watcher/
    ├── IncrementalReaderTests.swift       (T9)
    ├── VnodeWatcherTests.swift            (T9)
    ├── FSEventsWatcherTests.swift         (T9)
    ├── SessionRegistryTests.swift         (T9)
    ├── ReconcilerTests.swift              (T9)
    ├── JSONLWatcherIntegrationTests.swift (T9 端到端,用 tmp JSONL)
    └── ProjectsDirLayoutTests.swift       (T9)

Sources/CairnApp/CairnApp.swift            (T10 加 dev-only 环境变量 CAIRN_DEV_WATCH=1 开启 watcher + 日志)
```

**修改**:无其他文件。本 milestone **不动** UI / Services / Storage。

---

## 设计决策(pinned)

| # | 决策 | 理由 |
|---|---|---|
| 1 | **不改 Session 表 schema**,沿用 M1.2 的 `byte_offset` + `last_line_number` | 字段已准备好;M2.3 再接批量事务时也不需要改表 |
| 2 | **6 个组件按单一职责拆文件** | spec §3.2 模块方向严格;每文件 < 200 行便于 test / review |
| 3 | `FSEventsWatcher` 用 C API `FSEventStreamCreate` + Swift `class` 包 | 官方支持,低延迟;没有纯 Swift 原生替代 |
| 4 | per-file `VnodeWatcher` 用 `DispatchSourceFileSystemObject` | spec §4.2 明示的第二层;比 kqueue 简洁 |
| 5 | **永远不读半行的算法**:读 chunk → `split(Data: 0x0A)` → 若末字节 ≠ 0x0A,丢弃最后一片 → 偏移只推进完整行总字节数 | spec §4.2 "关键约束"原文 |
| 6 | `IncrementalReader` 是**纯函数** (static):`read(FileHandle, offset) -> (lines, newOffset, newLineCount)` | 便于单测 / 无副作用 |
| 7 | `Reconciler` 间隔 **30s**,非 MainActor;对比 DB `byte_offset` vs 文件 `lstat().st_size`,diff > 0 触发一次 ingest | spec §8.5 M2.1 验收条款 |
| 8 | watcher **不解析 JSONL 内容**,只发 `String` 行 | 严格范围控制;parser 是 M2.2 |
| 9 | watcher **不写 events 表**,只 `updateCursor` 自己的游标 | 严格范围控制;ingestor 是 M2.3 |
| 10 | 对外 API:`JSONLWatcher.events: AsyncStream<WatcherEvent>` 统一流 | Swift Concurrency 原生;上游直接 `for await`;M2.3 接入方便 |
| 11 | `WatcherEvent` 三种 case:`.discovered(Session)` / `.lines(sessionId, [String], lineNumberStart)` / `.removed(sessionId)` | 匹配 spec §4.2 三层监听产物 |
| 12 | **cursor 每次 ingest 后立即写 DB** | 崩溃恢复不丢数据;QPS 低(观察 Claude,不是我们自己高速写);SQLite 单行 upsert 毫秒级,可接受 |
| 13 | 新 session 发现时自动创建 `Session` row(workspace = 由 path hash 反推的或 fallback 到 default workspace),state=`.live`, byteOffset=0 | spec §2.6 Session 含路径/游标;fallback 到 `00000000-0000-0000-0000-000000000001` 直到 M3.5 真实 Workspace 管理就位 |
| 14 | Session **workspace 归属用"cwd 硬查 + hash 反推 + default 兜底"三层**(见 T8);没 JSONL system entry 时用 hash 目录反推,扫 JSONL 找首个 `system.cwd` 后修正 | M0.1 probe 22 hash 目录 vs 27 distinct cwd,hash 不可逆,但 system.cwd entry 100% 可得(Q1) |
| 15 | `ProjectsDirLayout` 的 **hash 规则**:cwd 中的 `/` `_` `.` 全替换为 `-`,正向可算 | M0.1 probe Q3 实测 |
| 16 | watcher 不对接 CairnApp 主体 UI,只在 `CAIRN_DEV_WATCH=1` env var 下启动 + stderr 日志 | 本 milestone 范围不涉及 Tab ↔ Session 绑定(M2.6);dev harness 够验收 |
| 17 | **关机**:`JSONLWatcher.stop()` 必须同步 flush cursor + 取消 FSEvents + 关所有 DispatchSource;在 `applicationWillTerminate` 调用 | 与 M1.5 willTerminate 布局保存对齐 |
| 18 | 单测**不启动真 FSEvents**,用假路径 + 假事件 + tmp 文件 append 模拟 | FSEvents 在 CI 不稳定(sandbox / 权限) |
| 19 | `JSONLWatcherIntegrationTests` 是**端到端** test:tmp 目录 + 真 vnode + 真 incremental read | 证明组件协作;跑在本地 macOS CI |
| 20 | 所有 actor 日志走 `swift-log`?**否** — 本 milestone 先用 stderr `FileHandle.standardError.write`,和 M1.5 对齐 | 避免引入日志基建;M2.7 打磨时统一到 swift-log |
| 21 | **`FSEventsWatcher.events()` / `VnodeWatcher.events()` 单订阅**(多次调用覆盖 continuation) | 这两个组件只被 `JSONLWatcher` 单一持有,单订阅足够;多订阅语义由 `JSONLWatcher.events()` 内部 fanout 提供 |
| 22 | `JSONLWatcher.events()` 用 `AsyncStream.makeStream(of:)`(Swift 5.9 API)而非 builder closure | builder closure 非 actor-isolated,内部访问 `continuations: [Continuation]` 违反 actor 隔离;makeStream 返回 (stream, continuation),actor 方法内同步 append 合法 |
| 23 | **`events()` 必须在 `start()` 之前调用** | start() 会触发初始 `scanExisting` 并 emit `.discovered` 事件;事件只发给当时已注册的 continuation,后注册的订阅者会漏初始发现。API 文档注释明示 |
| 24 | **`discover()` 必须先 `SessionDAO.fetch` 查已有 row,有则复用**,没有才 upsert 新 row | 否则每次 app 启动 discover 都把 `byte_offset` 覆盖为 0,cursor 持久化失效,watcher 会从头重读整份 JSONL(灾难) |

---

## 风险清单

| # | 风险 | 缓解 |
|---|---|---|
| 1 | FSEvents 在非签名 app 下可能要求"Full Disk Access" | `~/.claude/` 在用户 home 下,默认可读。若确实被系统拦截,README 加一行"授权全盘访问";v1 未签名走 xattr 路线已是非标 |
| 2 | `DispatchSourceFileSystemObject` 在文件被重命名 / unlink 后 handle 失效 | vnode observer 监听 `.delete` + `.rename`,触发时通过 FSEvents 重新 resolve 路径 |
| 3 | Claude Code 追加写 JSONL 可能**不以 \n 结束一行**的瞬间(部分写入)| 纯函数 `IncrementalReader` 丢弃不完整尾段,下次再读 |
| 4 | 30s reconcile 在窗口内错过的文件大小变化 | vnode 覆盖;reconcile 只是第三层兜底,双写不出错(cursor + size 比较后 no-op) |
| 5 | session 文件很大(> 100MB)首次 reconcile 扫描慢 | `read(upToCount: 1_MB)` 分块读;一次 tick 只读一块,下次 tick 继续 |
| 6 | 路径 hash 反推失败(新 cwd 含未见过的字符)| M0.1 probe 只见 `/ _ .`;fallback 到 default workspace;M2.6 做 Session ↔ Workspace 绑定时再细化 |
| 7 | 关机丢 cursor → 重启重复读老行 | `updateCursor` 每 chunk 立即写;若还漏,下次启动 reconcile 比较 DB offset 和 file size,只往前读,不重复(cursor 单调递增) |
| 8 | 活跃 session 数量大(> 100)导致 vnode source 泛滥 | M0.1 probe 517 个 session 里只有个位数活跃;若真达到上限用 LRU 淘汰。M2.1 不优化 |

---

## 对外 API 定义(固化,T7 完成后不改)

```swift
// Sources/CairnClaude/Watcher/JSONLWatcher.swift

public actor JSONLWatcher {
    public enum WatcherEvent: Sendable {
        /// watcher 首次发现该 session 文件(或 reconcile 发现落盘未注册)
        case discovered(Session)
        /// 增量读到一批 raw JSON 行。lineNumberStart 是这批行的第一条行号(1-based)
        case lines(sessionId: UUID, lines: [String], lineNumberStart: Int64)
        /// session 文件被删除(session 判 .crashed 留 M2.6)
        case removed(sessionId: UUID)
    }

    public init(database: CairnDatabase, projectsRoot: URL, defaultWorkspaceId: UUID)

    /// 对外唯一订阅点。多订阅者 → 每次调用返回独立 AsyncStream,事件 fanout
    /// 到所有活跃 continuation。**必须先于 start() 调用**,否则会漏掉
    /// start() 期间 scanExisting 产生的 .discovered 事件。
    public func events() -> AsyncStream<WatcherEvent>

    /// 启动:① 扫 projectsRoot 现有 JSONL 建 session 行并 emit .discovered
    /// ② 挂 FSEvents ③ 启 30s Reconciler
    public func start() async throws

    /// 停止:取消 FSEvents / 关所有 DispatchSource / 取消所有 background task
    /// / finish 所有 continuation。cursor 已在每次 ingest 时写 DB(async,
    /// 极端情况可能丢最后一 chunk,见 Known limitations)
    public func stop() async
}
```

M2.3 EventIngestor 会这样用:

```swift
let watcher = JSONLWatcher(database: db, projectsRoot: URL(fileURLWithPath: "\(NSHomeDirectory())/.claude/projects"))
try await watcher.start()
Task {
    for await event in watcher.events() {
        switch event {
        case .discovered(let session):    // M2.3 建 session row
        case .lines(let sid, let ls, _):  // M2.3 parser + event 批量 insert
        case .removed:                    // M2.6 标 crashed
        }
    }
}
```

---

## Tasks

### Task 1: M0.1 probe + spec §4.2 要点笔记

**Files**:
- Read: `docs/decisions/0001-probe-findings.md`
- Read: `docs/superpowers/specs/2026-04-23-cairn-v1-design.md:432-527`(§4.2–4.5)
- Create: `docs/superpowers/plans/notes/m2-1-probe-summary.md`(plan-local 笔记)

- [ ] **Step 1:** 读 ADR 0001 Q1 / Q3 / Q5 / Q6 / Q7,记录到 notes 文件:
  - Q1:`type=system` entry 的 `entry.cwd` 是 cwd 权威来源(不是 first line)
  - Q3:path hash 是 `/ _ .` → `-` 替换;正向可算,逆向歧义
  - Q5:11 种 JSONL 顶层 type,spec 只列 6 种;但本 milestone 不 parse,仅记录
  - Q6:session 大小 p95 ≈ 3MB,p99 ≈ 30MB(影响 T2 块读策略)
  - Q7:session 无 end 标记,末行多样(M2.6 才需要,本 milestone 略)
- [ ] **Step 2:** 跑 `ls -la ~/.claude/projects/ | head -5` 确认目录存在,记 hash dir 数量
- [ ] **Step 3:** commit

```bash
git add docs/superpowers/plans/notes/m2-1-probe-summary.md
git commit -m "docs(m2.1): probe summary for JSONLWatcher planning"
```

---

### Task 2: IncrementalReader(纯函数)

**Files**:
- Create: `Sources/CairnClaude/Watcher/IncrementalReader.swift`
- Create: `Tests/CairnClaudeTests/Watcher/IncrementalReaderTests.swift`

**关键不变量**:
- 返回的每一行**不含末尾 `\n`**
- 返回的 `newOffset` 必等于 `startOffset + (所有完整行连同各自末尾 \n 的总字节数)`
- 如果 chunk 末尾不是 `\n`,最后一片被丢弃,偏移不推进到它

- [ ] **Step 1: 写失败测试**

```swift
// Tests/CairnClaudeTests/Watcher/IncrementalReaderTests.swift
import XCTest
@testable import CairnClaude

final class IncrementalReaderTests: XCTestCase {
    private func makeTempFile(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inc-\(UUID().uuidString).jsonl")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func test_readsCompleteLines() throws {
        let url = try makeTempFile(#"""
        {"a":1}
        {"b":2}
        {"c":3}

        """#)  // 三行完整 + trailing \n
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 0, maxBytes: 1 << 20
        )
        XCTAssertEqual(result.lines, [#"{"a":1}"#, #"{"b":2}"#, #"{"c":3}"#])
        XCTAssertEqual(result.newOffset, 24)  // 8+8+8 = 24 字节
        XCTAssertEqual(result.linesRead, 3)
    }

    func test_dropsIncompleteTrailingLine() throws {
        // 最后一行没 \n,代表写入途中
        let url = try makeTempFile(#"""
        {"a":1}
        {"b":
        """#)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 0, maxBytes: 1 << 20
        )
        XCTAssertEqual(result.lines, [#"{"a":1}"#])
        XCTAssertEqual(result.newOffset, 8)  // 只推进第一行
    }

    func test_resumesFromOffset() throws {
        let url = try makeTempFile(#"""
        {"a":1}
        {"b":2}
        {"c":3}

        """#)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 8, maxBytes: 1 << 20  // skip first line
        )
        XCTAssertEqual(result.lines, [#"{"b":2}"#, #"{"c":3}"#])
        XCTAssertEqual(result.newOffset, 24)
    }

    func test_returnsEmptyWhenAtEOF() throws {
        let url = try makeTempFile(#"""
        {"a":1}

        """#)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 8, maxBytes: 1 << 20
        )
        XCTAssertEqual(result.lines, [])
        XCTAssertEqual(result.newOffset, 8)  // 未推进
        XCTAssertEqual(result.linesRead, 0)
    }

    func test_handlesEmptyLines() throws {
        // 真实 JSONL 里偶尔有空行
        let url = try makeTempFile("{\"a\":1}\n\n{\"b\":2}\n")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 0, maxBytes: 1 << 20
        )
        XCTAssertEqual(result.lines, [#"{"a":1}"#, "", #"{"b":2}"#])
        XCTAssertEqual(result.newOffset, 17)
    }

    func test_respectsMaxBytes() throws {
        // 10 行,每行 8 字节 = 80 字节;限 20 → 只读前 2 行
        let lines = (0..<10).map { #"{"n":\#($0)}"# }
        let url = try makeTempFile(lines.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 0, maxBytes: 20
        )
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.newOffset, 16)  // 2 行 × 8 字节
    }
}
```

- [ ] **Step 2: 运行测试,期望 FAIL**

```bash
swift test --filter IncrementalReaderTests
```
期望:`error: no such module 'IncrementalReader'` 或类似(类型不存在)。

- [ ] **Step 3: 实现**

```swift
// Sources/CairnClaude/Watcher/IncrementalReader.swift
import Foundation

/// 按字节偏移增量读取 JSONL 文件。纯函数,无状态。
///
/// 关键不变量(spec §4.2):
/// - **永远不读半行**:若 chunk 末字节 ≠ `\n`,最后一片被丢弃
/// - `newOffset` 仅推进到最后一行完整的 `\n` 之后
/// - 返回行**不含** trailing `\n`
public enum IncrementalReader {
    public struct Result: Equatable {
        public let lines: [String]
        public let newOffset: Int64
        public let linesRead: Int64
    }

    public enum ReadError: Error, Equatable {
        case cannotOpen(String)
        case seekFailed(Int64)
    }

    /// 从 `fromOffset` 读最多 `maxBytes` 字节,返回完整行 + 推进后的偏移。
    public static func read(
        fileURL: URL,
        fromOffset: Int64,
        maxBytes: Int
    ) throws -> Result {
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else {
            throw ReadError.cannotOpen(fileURL.path)
        }
        defer { try? fh.close() }

        try fh.seek(toOffset: UInt64(fromOffset))
        guard let chunk = try fh.read(upToCount: maxBytes), !chunk.isEmpty else {
            return Result(lines: [], newOffset: fromOffset, linesRead: 0)
        }

        // Data.split(separator:omittingEmpty:false) 保留所有分段。两种边界:
        //  - chunk 以 \n 结尾:segments 最后一段是 \n 之后的空(丢)
        //  - chunk 不以 \n 结尾:segments 最后一段是不完整行(也丢)
        // 两种情况统一 removeLast。
        let newline: UInt8 = 0x0A
        var segments = chunk.split(
            separator: newline,
            omittingEmptySubsequences: false
        )
        if !segments.isEmpty {
            segments.removeLast()
        }

        // 完整行总字节数 = 各 segment 字节数之和 + 行数(每行各 1 字节 \n)
        let completeBytes = segments.reduce(0) { $0 + $1.count } + segments.count
        let lines = segments.map { String(decoding: $0, as: UTF8.self) }

        return Result(
            lines: lines,
            newOffset: fromOffset + Int64(completeBytes),
            linesRead: Int64(lines.count)
        )
    }
}
```

- [ ] **Step 4: 运行测试,期望 PASS**

```bash
swift test --filter IncrementalReaderTests
```
期望:6 个 test pass,0 fail。

- [ ] **Step 5: commit**

```bash
git add Sources/CairnClaude/Watcher/IncrementalReader.swift Tests/CairnClaudeTests/Watcher/IncrementalReaderTests.swift
git commit -m "feat(m2.1): IncrementalReader — byte-offset JSONL reader, never reads half-lines"
```

---

### Task 3: VnodeWatcher(per-file DispatchSource)

**Files**:
- Create: `Sources/CairnClaude/Watcher/VnodeWatcher.swift`
- Create: `Tests/CairnClaudeTests/Watcher/VnodeWatcherTests.swift`

**要点**:
- `DispatchSourceFileSystemObject` 监听 `.write | .extend | .delete | .rename`
- 事件以 `AsyncStream<VnodeEvent>` 发出
- `stop()` 取消 source,关 fd

- [ ] **Step 1: 写失败测试**

```swift
// Tests/CairnClaudeTests/Watcher/VnodeWatcherTests.swift
import XCTest
@testable import CairnClaude

final class VnodeWatcherTests: XCTestCase {
    private var tmpURL: URL!

    override func setUp() async throws {
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vnode-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: tmpURL.path, contents: Data())
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpURL)
    }

    func test_writeTriggersEvent() async throws {
        let watcher = try VnodeWatcher(fileURL: tmpURL)
        let stream = watcher.events()
        let task = Task { () -> VnodeWatcher.VnodeEvent? in
            for await ev in stream { return ev }
            return nil
        }

        // 等 source 挂上
        try await Task.sleep(for: .milliseconds(100))

        // append
        let fh = try FileHandle(forWritingTo: tmpURL)
        try fh.seekToEnd()
        try fh.write(contentsOf: Data("hello\n".utf8))
        try fh.close()

        let got = try await withTimeout(seconds: 2) {
            await task.value
        }
        guard let got = got else { XCTFail("no vnode event"); return }
        XCTAssertTrue(got == .write || got == .extend, "got \(got)")
        watcher.stop()
    }

    func test_deleteTriggersEvent() async throws {
        let watcher = try VnodeWatcher(fileURL: tmpURL)
        let stream = watcher.events()
        let task = Task { () -> [VnodeWatcher.VnodeEvent] in
            var collected: [VnodeWatcher.VnodeEvent] = []
            for await ev in stream {
                collected.append(ev)
                if collected.count >= 1 { break }
            }
            return collected
        }

        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.removeItem(at: tmpURL)

        let got = try await withTimeout(seconds: 2) { await task.value }
        XCTAssertTrue(got.contains(.delete) || got.contains(.rename))
        watcher.stop()
    }

    // 小工具
    private func withTimeout<T: Sendable>(
        seconds: Double, _ body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
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

- [ ] **Step 2: 运行测试,期望 FAIL**

```bash
swift test --filter VnodeWatcherTests
```

- [ ] **Step 3: 实现**

```swift
// Sources/CairnClaude/Watcher/VnodeWatcher.swift
import Foundation

/// Per-file vnode 监听器。spec §4.2 第二层兜底。
/// DispatchSourceFileSystemObject `.write | .extend | .delete | .rename`。
public final class VnodeWatcher: @unchecked Sendable {
    public enum VnodeEvent: Sendable, Equatable {
        case write, extend, delete, rename
    }

    public enum VnodeError: Error {
        case openFailed(String)
    }

    private let fd: Int32
    private let source: DispatchSourceFileSystemObject
    private var continuation: AsyncStream<VnodeEvent>.Continuation?
    private let lock = NSLock()

    public init(fileURL: URL) throws {
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { throw VnodeError.openFailed(fileURL.path) }
        self.fd = fd
        self.source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
    }

    /// **单订阅**:多次调用会覆盖前一个 continuation。本 watcher 只被
    /// `JSONLWatcher` 单一持有,此约束无实际影响。
    public func events() -> AsyncStream<VnodeEvent> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            source.setEventHandler { [weak self] in
                guard let self = self else { return }
                let mask = self.source.data
                if mask.contains(.write)  { continuation.yield(.write)  }
                if mask.contains(.extend) { continuation.yield(.extend) }
                if mask.contains(.delete) { continuation.yield(.delete); continuation.finish() }
                if mask.contains(.rename) { continuation.yield(.rename); continuation.finish() }
            }
            source.setCancelHandler { [fd = self.fd] in close(fd) }
            source.resume()
        }
    }

    public func stop() {
        if !source.isCancelled { source.cancel() }
        lock.lock()
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

    deinit { stop() }
}
```

- [ ] **Step 4: 运行测试,期望 PASS**

```bash
swift test --filter VnodeWatcherTests
```

- [ ] **Step 5: commit**

```bash
git add Sources/CairnClaude/Watcher/VnodeWatcher.swift Tests/CairnClaudeTests/Watcher/VnodeWatcherTests.swift
git commit -m "feat(m2.1): VnodeWatcher — DispatchSourceFileSystemObject per-file trigger"
```

---

### Task 4: FSEventsWatcher(C API wrap)

**Files**:
- Create: `Sources/CairnClaude/Watcher/FSEventsWatcher.swift`
- Create: `Tests/CairnClaudeTests/Watcher/FSEventsWatcherTests.swift`

**要点**:
- 目录树 `kFSEventStreamCreateFlagFileEvents` 拿 per-file 事件
- 关心 `kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed`
- 过滤:只发 `.jsonl` 后缀 + 排除 `/tmp/` 无关前缀
- 事件以 `AsyncStream<FSEvent>` 发出

- [ ] **Step 1: 写失败测试**

```swift
// Tests/CairnClaudeTests/Watcher/FSEventsWatcherTests.swift
import XCTest
@testable import CairnClaude

final class FSEventsWatcherTests: XCTestCase {
    private var rootURL: URL!

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func test_detectsNewJsonlFile() async throws {
        let watcher = try FSEventsWatcher(rootURL: rootURL)
        let stream = watcher.events()
        try watcher.start()
        defer { watcher.stop() }

        // 等 FSEventStream 上线
        try await Task.sleep(for: .milliseconds(500))

        // 创建 session 子目录 + JSONL
        let sessionDir = rootURL.appendingPathComponent("-Users-alice-proj")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent("some-session.jsonl")
        try "hello\n".write(to: jsonl, atomically: true, encoding: .utf8)

        // 等事件
        let event = try await withTimeout(seconds: 5) { () -> FSEventsWatcher.FSEvent? in
            for await ev in stream {
                if case .created(let url) = ev, url.lastPathComponent.hasSuffix(".jsonl") {
                    return ev
                }
            }
            return nil
        }
        XCTAssertNotNil(event)
        if case .created(let url) = event {
            XCTAssertEqual(url.lastPathComponent, "some-session.jsonl")
        }
    }

    func test_filtersOutNonJsonl() async throws {
        let watcher = try FSEventsWatcher(rootURL: rootURL)
        let stream = watcher.events()
        try watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(500))

        let other = rootURL.appendingPathComponent("ignore.txt")
        try "x".write(to: other, atomically: true, encoding: .utf8)

        // 1 秒窗口内 collect 所有事件(for-await 永远不会自己 return,
        // 需显式用 Task + cancel 终止,而不是给 timeout body 套 for-await
        // —— 后者的 body 会一直等导致 timeout 抛 CancellationError 把 test 挂掉)。
        let collect = Task { () -> [FSEventsWatcher.FSEvent] in
            var acc: [FSEventsWatcher.FSEvent] = []
            for await ev in stream {
                acc.append(ev)
                if acc.count > 20 { break }
            }
            return acc
        }
        try await Task.sleep(for: .seconds(1))
        collect.cancel()
        let events = await collect.value
        let jsonlEvents = events.filter {
            if case .created(let url) = $0 { return url.lastPathComponent.hasSuffix(".jsonl") }
            return false
        }
        XCTAssertTrue(jsonlEvents.isEmpty, "expected no .jsonl events, got \(jsonlEvents)")
    }

    private func withTimeout<T: Sendable>(
        seconds: Double, _ body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
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

- [ ] **Step 2: 运行测试,期望 FAIL**

```bash
swift test --filter FSEventsWatcherTests
```

- [ ] **Step 3: 实现**

```swift
// Sources/CairnClaude/Watcher/FSEventsWatcher.swift
import Foundation
import CoreServices

/// 根目录 FSEvents 监听器。spec §4.2 第一层。
public final class FSEventsWatcher: @unchecked Sendable {
    public enum FSEvent: Sendable, Equatable {
        case created(URL), removed(URL), renamed(URL)
    }

    public enum FSEventsError: Error {
        case streamCreateFailed
    }

    private let rootURL: URL
    private var stream: FSEventStreamRef?
    private var continuation: AsyncStream<FSEvent>.Continuation?
    private var contextPtr: UnsafeMutablePointer<FSEventStreamContext>?
    private let lock = NSLock()
    private var isStarted = false

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
    }

    /// **单订阅**:多次调用会覆盖前一个 continuation,前一个 stream 不再收事件。
    /// 本 watcher 只被 `JSONLWatcher` 单一持有,此约束无实际影响。
    public func events() -> AsyncStream<FSEvent> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    public func start() throws {
        guard !isStarted else { return }
        isStarted = true

        let context = UnsafeMutablePointer<FSEventStreamContext>.allocate(capacity: 1)
        context.pointee = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        self.contextPtr = context

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<NSArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            for i in 0..<numEvents {
                let path = paths[i]
                let flags = eventFlags[i]
                let url = URL(fileURLWithPath: path)
                guard url.pathExtension == "jsonl" else { continue }
                if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                    watcher.emit(.created(url))
                }
                if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                    watcher.emit(.removed(url))
                }
                if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                    watcher.emit(.renamed(url))
                }
            }
        }

        let pathsToWatch = [rootURL.path] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,  // latency
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else {
            throw FSEventsError.streamCreateFailed
        }
        self.stream = stream

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    private func emit(_ event: FSEvent) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(event)
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        if let ptr = contextPtr {
            ptr.deallocate()
            contextPtr = nil
        }
        lock.lock()
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

    deinit { stop() }
}
```

- [ ] **Step 4: 运行测试,期望 PASS**

```bash
swift test --filter FSEventsWatcherTests
```

- [ ] **Step 5: commit**

```bash
git add Sources/CairnClaude/Watcher/FSEventsWatcher.swift Tests/CairnClaudeTests/Watcher/FSEventsWatcherTests.swift
git commit -m "feat(m2.1): FSEventsWatcher — root directory FSEvents stream with .jsonl filter"
```

---

### Task 5: SessionRegistry(活跃 session 内存状态)

**Files**:
- Create: `Sources/CairnClaude/Watcher/SessionRegistry.swift`
- Create: `Tests/CairnClaudeTests/Watcher/SessionRegistryTests.swift`

**要点**:actor,持有:
- `[sessionId: Session]` 活跃集
- `[jsonlPath: sessionId]` 路径反查
- 方法:`register(session)` / `advance(sessionId, newOffset, newLineCount)` / `unregister(sessionId)` / `lookup(path)`

- [ ] **Step 1: 写失败测试**

```swift
// Tests/CairnClaudeTests/Watcher/SessionRegistryTests.swift
import XCTest
import CairnCore
@testable import CairnClaude

final class SessionRegistryTests: XCTestCase {
    func test_registerAndLookup() async throws {
        let reg = SessionRegistry()
        let sid = UUID()
        let session = Session(
            id: sid,
            workspaceId: UUID(),
            jsonlPath: "/tmp/a.jsonl",
            startedAt: Date(),
            byteOffset: 0,
            lastLineNumber: 0,
            state: .live
        )
        await reg.register(session)
        let found = await reg.lookup(path: "/tmp/a.jsonl")
        XCTAssertEqual(found?.id, sid)
    }

    func test_advanceUpdatesCursor() async throws {
        let reg = SessionRegistry()
        let sid = UUID()
        await reg.register(Session(
            id: sid, workspaceId: UUID(), jsonlPath: "/tmp/b.jsonl",
            startedAt: Date(), byteOffset: 0, lastLineNumber: 0, state: .live
        ))
        await reg.advance(sessionId: sid, newOffset: 100, linesRead: 5)
        let s = await reg.get(sessionId: sid)
        XCTAssertEqual(s?.byteOffset, 100)
        XCTAssertEqual(s?.lastLineNumber, 5)
    }

    func test_unregisterRemovesBothIndices() async throws {
        let reg = SessionRegistry()
        let sid = UUID()
        await reg.register(Session(
            id: sid, workspaceId: UUID(), jsonlPath: "/tmp/c.jsonl",
            startedAt: Date(), byteOffset: 0, lastLineNumber: 0, state: .live
        ))
        await reg.unregister(sessionId: sid)
        let byId = await reg.get(sessionId: sid)
        let byPath = await reg.lookup(path: "/tmp/c.jsonl")
        XCTAssertNil(byId)
        XCTAssertNil(byPath)
    }
}
```

- [ ] **Step 2: 运行测试,期望 FAIL**

- [ ] **Step 3: 实现**

```swift
// Sources/CairnClaude/Watcher/SessionRegistry.swift
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
```

- [ ] **Step 4: 运行测试,期望 PASS**

- [ ] **Step 5: commit**

```bash
git add Sources/CairnClaude/Watcher/SessionRegistry.swift Tests/CairnClaudeTests/Watcher/SessionRegistryTests.swift
git commit -m "feat(m2.1): SessionRegistry — in-memory cursor/path index actor"
```

---

### Task 6: Reconciler(30s 兜底)

**Files**:
- Create: `Sources/CairnClaude/Watcher/Reconciler.swift`
- Create: `Tests/CairnClaudeTests/Watcher/ReconcilerTests.swift`

**要点**:
- 非 MainActor;独立 `Task` + `Task.sleep(for:)` 循环
- 每 tick:`SessionDAO.fetchActive` + 对每个 session `lstat()` 文件 → 如文件 size > registry 里的 byteOffset,触发一次 ingest 回调
- 对外:`init(interval:onTick:)` + `start()` / `stop()`
- 单测可传 50ms interval 跑几 tick

- [ ] **Step 1: 写失败测试**

```swift
// Tests/CairnClaudeTests/Watcher/ReconcilerTests.swift
import XCTest
@testable import CairnClaude

final class ReconcilerTests: XCTestCase {
    func test_firesCallbackAtInterval() async throws {
        let counter = AsyncCounter()
        let reconciler = Reconciler(interval: .milliseconds(50)) {
            await counter.inc()
        }
        await reconciler.start()
        try await Task.sleep(for: .milliseconds(180))
        await reconciler.stop()
        let n = await counter.value
        XCTAssertGreaterThanOrEqual(n, 2)
        XCTAssertLessThanOrEqual(n, 5)  // 180ms / 50ms ≈ 3-4
    }

    func test_stopHaltsCallbacks() async throws {
        let counter = AsyncCounter()
        let reconciler = Reconciler(interval: .milliseconds(50)) {
            await counter.inc()
        }
        await reconciler.start()
        try await Task.sleep(for: .milliseconds(80))
        await reconciler.stop()
        let n1 = await counter.value
        try await Task.sleep(for: .milliseconds(200))
        let n2 = await counter.value
        XCTAssertEqual(n1, n2)
    }
}

private actor AsyncCounter {
    private(set) var value = 0
    func inc() { value += 1 }
}
```

- [ ] **Step 2: 运行测试,期望 FAIL**

- [ ] **Step 3: 实现**

```swift
// Sources/CairnClaude/Watcher/Reconciler.swift
import Foundation

/// 每 N 秒 tick 一次,调回调做兜底扫描。spec §4.2 第三层。
public actor Reconciler {
    private let interval: Duration
    private let onTick: @Sendable () async -> Void
    private var task: Task<Void, Never>?

    public init(interval: Duration, onTick: @Sendable @escaping () async -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [interval, onTick] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                await onTick()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
```

- [ ] **Step 4: 运行测试,期望 PASS**

- [ ] **Step 5: commit**

```bash
git add Sources/CairnClaude/Watcher/Reconciler.swift Tests/CairnClaudeTests/Watcher/ReconcilerTests.swift
git commit -m "feat(m2.1): Reconciler — N-second bounded ticker actor"
```

---

### Task 7: JSONLWatcher 总装

**Files**:
- Create: `Sources/CairnClaude/Watcher/JSONLWatcher.swift`
- Create: `Tests/CairnClaudeTests/Watcher/JSONLWatcherIntegrationTests.swift`

**要点**:
- `actor JSONLWatcher` 持有 `database` / `projectsRoot` / `registry` / `fsWatcher` / `[URL: VnodeWatcher]` / `reconciler`
- `start()`:① 初始扫描 `projectsRoot` 所有已存在 .jsonl → discover + 建 registry ② 启 FSEvents ③ 启 Reconciler ④ 对每个已知 session 挂 VnodeWatcher ⑤ 全部子任务
- `events()` AsyncStream 对外单点订阅(多订阅 → 多个独立 stream,用 continuation 数组)
- `stop()`:取消所有子 task、flush cursor 到 DB、关 streams
- 对每次 `VnodeEvent.write/extend`:`IncrementalReader.read(fromOffset: session.byteOffset)` → `emit .lines(...)` + `updateCursor` + `registry.advance`

- [ ] **Step 1: 写集成测试(端到端,用真 vnode + 真 FS 但假 db)**

```swift
// Tests/CairnClaudeTests/Watcher/JSONLWatcherIntegrationTests.swift
import XCTest
import CairnCore
import CairnStorage
@testable import CairnClaude

final class JSONLWatcherIntegrationTests: XCTestCase {
    private var rootURL: URL!
    private var db: CairnDatabase!
    private let defaultWsId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        db = try await CairnDatabase(
            location: .inMemory, migrator: CairnStorage.makeMigrator()
        )
        // bootstrap default workspace(FK 约束)
        try await WorkspaceDAO.upsert(
            Workspace(id: defaultWsId, name: "Default", cwd: NSHomeDirectory()),
            in: db
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func test_discoversExistingSessionOnStart() async throws {
        // 先写一个 session 文件
        let sessionDir = rootURL.appendingPathComponent("-Users-alice")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent("s1.jsonl")
        try "{\"type\":\"user\"}\n".write(to: jsonl, atomically: true, encoding: .utf8)

        let watcher = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let stream = await watcher.events()
        try await watcher.start()
        defer { Task { await watcher.stop() } }

        let first = try await withTimeout(seconds: 3) { () -> JSONLWatcher.WatcherEvent? in
            for await ev in stream {
                if case .discovered = ev { return ev }
            }
            return nil
        }
        guard case .discovered(let session) = first else {
            return XCTFail("no discovery")
        }
        XCTAssertEqual(session.jsonlPath, jsonl.path)
    }

    func test_yieldsNewLinesOnAppend() async throws {
        let sessionDir = rootURL.appendingPathComponent("-Users-bob")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent("s2.jsonl")
        try "{\"type\":\"user\"}\n".write(to: jsonl, atomically: true, encoding: .utf8)

        let watcher = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let stream = await watcher.events()
        try await watcher.start()
        defer { Task { await watcher.stop() } }

        // 等 discovery
        _ = try await withTimeout(seconds: 3) { () -> Bool in
            for await ev in stream {
                if case .discovered = ev { return true }
            }
            return false
        }

        // append
        let fh = try FileHandle(forWritingTo: jsonl)
        try fh.seekToEnd()
        try fh.write(contentsOf: Data("{\"type\":\"assistant\"}\n".utf8))
        try fh.close()

        // 等 lines 事件
        let lines = try await withTimeout(seconds: 5) { () -> [String]? in
            for await ev in stream {
                if case .lines(_, let ls, _) = ev, !ls.isEmpty { return ls }
            }
            return nil
        }
        XCTAssertEqual(lines, [#"{"type":"assistant"}"#])
    }

    /// 回归测试:**必须**证明 discover 不会把已有 byte_offset 覆盖为 0。
    /// 首次测试 watcher 读完几行 → stop → 再起一个新 watcher 实例 →
    /// discover 同一个文件,应复用 byte_offset,不重复发已读过的行。
    func test_reusesCursorOnRediscover() async throws {
        let sessionDir = rootURL.appendingPathComponent("-Users-reuse")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent(UUID().uuidString + ".jsonl")
        try "{\"a\":1}\n{\"b\":2}\n".write(to: jsonl, atomically: true, encoding: .utf8)

        // 第一轮:read 两行 → stop
        do {
            let w1 = JSONLWatcher(
                database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
            )
            let stream = await w1.events()
            try await w1.start()
            let collect = Task { () -> [String] in
                var acc: [String] = []
                for await ev in stream {
                    if case .lines(_, let ls, _) = ev { acc.append(contentsOf: ls) }
                    if acc.count >= 2 { break }
                }
                return acc
            }
            // 触发一次 ingest(Vnode 未触发时,reconciler 会来兜底;为了快速
            // 用对文件的 no-op touch 触发 vnode,或依赖 start 时的首次 scan
            // —— 此处用 reconciler 但要等。为了 test 快,改用直接 append 触发 vnode)
            try await Task.sleep(for: .milliseconds(300))
            let fh = try FileHandle(forWritingTo: jsonl)
            try fh.seekToEnd()
            try fh.write(contentsOf: Data("{\"c\":3}\n".utf8))  // 触发 vnode
            try fh.close()
            let got = try await withTimeout(seconds: 5) { await collect.value }
            XCTAssertTrue(got.contains(#"{"a":1}"#) && got.contains(#"{"b":2}"#))
            // 等 pending ingest 的 async updateCursor 落盘,否则 stop 之后
            // DB 里 byte_offset 可能还是旧值,下一轮误判为 "从头读"
            try await Task.sleep(for: .milliseconds(300))
            await w1.stop()
        }

        // 检查 DB:应有 session row,byte_offset > 0
        let sessionId = UUID(uuidString: jsonl.deletingPathExtension().lastPathComponent)!
        let saved = try await SessionDAO.fetch(id: sessionId, in: db)
        XCTAssertNotNil(saved)
        let offsetAfterFirstRun = saved!.byteOffset
        XCTAssertGreaterThan(offsetAfterFirstRun, 0)

        // 第二轮:新 watcher 实例,**不应**把 byte_offset 覆盖为 0,
        // **不应**重复 yield 第一轮已读过的 {a:1} {b:2} {c:3}
        let w2 = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let stream2 = await w2.events()
        try await w2.start()
        defer { Task { await w2.stop() } }

        // 等 1 秒看是否有误发 lines
        let collect2 = Task { () -> [String] in
            var acc: [String] = []
            for await ev in stream2 {
                if case .lines(_, let ls, _) = ev { acc.append(contentsOf: ls) }
                if acc.count > 10 { break }
            }
            return acc
        }
        try await Task.sleep(for: .seconds(1))
        collect2.cancel()
        let extra = await collect2.value
        XCTAssertTrue(extra.isEmpty, "should not re-yield already-read lines, got \(extra)")

        // 再次读 DB,byte_offset 应 ≥ 第一轮值(未被覆盖)
        let saved2 = try await SessionDAO.fetch(id: sessionId, in: db)
        XCTAssertEqual(saved2?.byteOffset, offsetAfterFirstRun)
    }

    func test_persistsCursorToDb() async throws {
        let sessionDir = rootURL.appendingPathComponent("-Users-carol")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent("s3.jsonl")
        try "{\"type\":\"user\"}\n".write(to: jsonl, atomically: true, encoding: .utf8)

        let watcher = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let stream = await watcher.events()
        try await watcher.start()
        defer { Task { await watcher.stop() } }

        // 收集至少 .lines 一次
        let task = Task { () -> UUID? in
            for await ev in stream {
                if case .lines(let sid, _, _) = ev { return sid }
            }
            return nil
        }

        // append trigger
        try await Task.sleep(for: .milliseconds(300))
        let fh = try FileHandle(forWritingTo: jsonl)
        try fh.seekToEnd()
        try fh.write(contentsOf: Data("{\"type\":\"assistant\"}\n".utf8))
        try fh.close()

        let sid = try await withTimeout(seconds: 5) { await task.value }
        XCTAssertNotNil(sid)

        // check db
        let saved = try await SessionDAO.fetch(id: sid!, in: db)
        XCTAssertNotNil(saved)
        XCTAssertGreaterThan(saved!.byteOffset, 0)
        XCTAssertGreaterThan(saved!.lastLineNumber, 0)
    }

    private func withTimeout<T: Sendable>(
        seconds: Double, _ body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
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

- [ ] **Step 2: 运行测试,期望 FAIL**

- [ ] **Step 3: 实现**

```swift
// Sources/CairnClaude/Watcher/JSONLWatcher.swift
import Foundation
import CairnCore
import CairnStorage

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
    /// 产生的 `.discovered` 事件。用 `AsyncStream.makeStream(of:)`(Swift 5.9)
    /// 而非 builder closure —— builder closure 是非 isolated,内部访问 actor
    /// state `continuations` 会违反 actor 隔离(编译错)。
    public func events() -> AsyncStream<WatcherEvent> {
        let (stream, cont) = AsyncStream.makeStream(of: WatcherEvent.self)
        continuations.append(cont)
        return stream
    }

    public func start() async throws {
        // 1. 初始扫描已存在文件
        let existing = try await scanExisting()
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
        // flush cursor:registry 已同步每次 advance 后写 DB,这里无额外动作
    }

    // MARK: - 内部

    private func emit(_ event: WatcherEvent) {
        for cont in continuations { cont.yield(event) }
    }

    private func scanExisting() async throws -> [URL] {
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
        // 已注册?跳过
        if await registry.lookup(path: jsonlURL.path) != nil { return }

        // 反推 workspace:M2.1 简化 — 用 default workspace;M2.6 升级
        let wsId = defaultWorkspaceId

        // 创建或复用 session。session id 用 JSONL 文件名(不带扩展)—— Claude Code 用
        // UUID 作为 session id 并以此命名文件,可直接复用
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
            break  // M2.6 处理
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
```

- [ ] **Step 4: 运行测试,期望 PASS**

```bash
swift test --filter JSONLWatcherIntegrationTests
```

- [ ] **Step 5: commit**

```bash
git add Sources/CairnClaude/Watcher/JSONLWatcher.swift Tests/CairnClaudeTests/Watcher/JSONLWatcherIntegrationTests.swift
git commit -m "feat(m2.1): JSONLWatcher — 3-layer orchestrator actor with AsyncStream events"
```

---

### Task 8: ProjectsDirLayout(hash 工具)

**Files**:
- Create: `Sources/CairnClaude/Watcher/ProjectsDirLayout.swift`
- Create: `Tests/CairnClaudeTests/Watcher/ProjectsDirLayoutTests.swift`

**要点**:纯函数
- `hash(cwd:) -> String`:`/` `_` `.` → `-`
- `isReverseAmbiguous(hash:) -> Bool`:含 `-` 就歧义

- [ ] **Step 1: 写失败测试**

```swift
// Tests/CairnClaudeTests/Watcher/ProjectsDirLayoutTests.swift
import XCTest
@testable import CairnClaude

final class ProjectsDirLayoutTests: XCTestCase {
    func test_hashReplacesSlashesUnderscoresDotsWithDashes() {
        XCTAssertEqual(
            ProjectsDirLayout.hash(cwd: "/Users/sorain"),
            "-Users-sorain"
        )
        XCTAssertEqual(
            ProjectsDirLayout.hash(cwd: "/Users/sorain/.vext/workspaces/01KN/mvp"),
            "-Users-sorain--vext-workspaces-01KN-mvp"
        )
        XCTAssertEqual(
            ProjectsDirLayout.hash(cwd: "/tmp/with_under_scores"),
            "-tmp-with-under-scores"
        )
    }

    func test_hashIsIdempotent() {
        let once = ProjectsDirLayout.hash(cwd: "/a/b.c")
        let twice = ProjectsDirLayout.hash(cwd: once)
        XCTAssertEqual(once, "-a-b-c")
        // twice 含 `-`,结果仍然只是多一个 `-` 前缀(验证逆向不唯一)
        XCTAssertNotEqual(once, twice)
    }
}
```

- [ ] **Step 2: 运行测试,期望 FAIL**

- [ ] **Step 3: 实现**

```swift
// Sources/CairnClaude/Watcher/ProjectsDirLayout.swift
import Foundation

/// ~/.claude/projects/{hash}/ 的 hash 规则。M0.1 probe 实测:`/` `_` `.` → `-`。
public enum ProjectsDirLayout {
    public static func hash(cwd: String) -> String {
        var result = ""
        result.reserveCapacity(cwd.count)
        for ch in cwd {
            if ch == "/" || ch == "_" || ch == "." { result.append("-") }
            else { result.append(ch) }
        }
        return result
    }
}
```

- [ ] **Step 4: 运行测试,期望 PASS**

- [ ] **Step 5: commit**

```bash
git add Sources/CairnClaude/Watcher/ProjectsDirLayout.swift Tests/CairnClaudeTests/Watcher/ProjectsDirLayoutTests.swift
git commit -m "feat(m2.1): ProjectsDirLayout — forward-only hash rule (M0.1 probe Q3)"
```

---

### Task 9: 单测审查

**Files**:
- 本 milestone 所有 test 文件

- [ ] **Step 1: 跑完整测试套件**

```bash
swift test 2>&1 | tail -5
```
期望:`Executed N tests, with 0 failures`,N ≥ 120 + 21 = 141。

新增 M2.1 测试分布:
- IncrementalReader:6 个
- VnodeWatcher:2 个
- FSEventsWatcher:2 个
- SessionRegistry:3 个
- Reconciler:2 个
- JSONLWatcherIntegration:4 个(含回归 `test_reusesCursorOnRediscover`)
- ProjectsDirLayout:2 个
- 共 21 个

- [ ] **Step 2: 单独过 M2.1 测试**

```bash
swift test --filter CairnClaudeTests 2>&1 | grep "Executed"
```
期望:≥ 21 tests pass。

- [ ] **Step 3:** 若有 flaky(vnode 时序)test,加 `Task.sleep(for: .milliseconds(500))` 缓冲;不 skip。

---

### Task 10: Dev-only harness

**Files**:
- Modify: `Package.swift`(加 `CairnClaude` 到 CairnApp 依赖)
- Modify: `Sources/CairnApp/CairnApp.swift`

**要点**:
- `env(CAIRN_DEV_WATCH=1)` 启动时在 `initializeDatabase` 末尾跑 `JSONLWatcher` 并 stderr 打印每个 WatcherEvent
- 非 dev 环境完全不启动

- [ ] **Step 0: 更新 Package.swift**

```swift
// Before:
.executableTarget(
    name: "CairnApp",
    dependencies: ["CairnCore", "CairnUI", "CairnTerminal", "CairnStorage"]
),
// After:
.executableTarget(
    name: "CairnApp",
    dependencies: ["CairnCore", "CairnUI", "CairnTerminal", "CairnStorage", "CairnClaude"]
),
```

- [ ] **Step 1: 修改 CairnApp.swift,在 `initializeDatabase` 最末尾加**

```swift
        // M2.1 dev harness:CAIRN_DEV_WATCH=1 启用 watcher 日志
        if ProcessInfo.processInfo.environment["CAIRN_DEV_WATCH"] == "1",
           let db = appDelegate.database {
            let root = URL(fileURLWithPath: "\(NSHomeDirectory())/.claude/projects")
            let watcher = JSONLWatcher(
                database: db,
                projectsRoot: root,
                defaultWorkspaceId: appDelegate.defaultWorkspaceId
            )
            appDelegate.jsonlWatcher = watcher
            do {
                try await watcher.start()
                FileHandle.standardError.write(Data("[JSONLWatcher] started on \(root.path)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("[JSONLWatcher] start failed: \(error)\n".utf8))
            }
            Task {
                for await event in await watcher.events() {
                    switch event {
                    case .discovered(let s):
                        FileHandle.standardError.write(Data(
                            "[JSONLWatcher] discovered \(s.id) at \(s.jsonlPath)\n".utf8
                        ))
                    case .lines(let sid, let ls, let start):
                        FileHandle.standardError.write(Data(
                            "[JSONLWatcher] +\(ls.count) lines for \(sid) (from #\(start))\n".utf8
                        ))
                    case .removed(let sid):
                        FileHandle.standardError.write(Data(
                            "[JSONLWatcher] removed \(sid)\n".utf8
                        ))
                    }
                }
            }
        }
```

- [ ] **Step 2: 在 `CairnAppDelegate` 加字段**

```swift
    var jsonlWatcher: JSONLWatcher?
```

- [ ] **Step 3: 在 `applicationWillTerminate` 加 stop**

```swift
    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            saveLayoutNow(reason: "willTerminate")
            if let watcher = jsonlWatcher {
                Task { await watcher.stop() }  // 不阻塞退出;cursor 已每次 advance 同步写
            }
        }
    }
```

- [ ] **Step 4: build verify**

```bash
swift build
```

- [ ] **Step 5: commit**

```bash
git add Package.swift Sources/CairnApp/CairnApp.swift
git commit -m "feat(m2.1): CAIRN_DEV_WATCH=1 env harness for manual JSONLWatcher verify"
```

---

### Task 11: scaffoldVersion bump

**Files**:
- Modify: `Sources/CairnCore/CairnCore.swift`
- Modify: 相关 test 断言

- [ ] **Step 1: 找所有 scaffoldVersion 断言**

```bash
grep -rn "0.5.0-m1.5\|scaffoldVersion" Sources/ Tests/ | head
```

- [ ] **Step 2: 全文替换 `0.5.0-m1.5` → `0.6.0-m2.1`**

- [ ] **Step 3: build + test**

```bash
swift build && swift test 2>&1 | grep "Executed"
```

- [ ] **Step 4: commit**

```bash
git add -A
git commit -m "chore(core): scaffoldVersion 0.5.0-m1.5 → 0.6.0-m2.1"
```

---

### Task 12: build + test + 真实 Claude 触发自检

- [ ] **Step 1: Clean build**

```bash
swift package clean && swift build
```
期望:`Build complete!`,无 warning(若有非 deprecation 的 warning,分析是否本 milestone 引入)。

- [ ] **Step 2: 全测试**

```bash
swift test 2>&1 | grep -E "Executed.*tests|FAIL"
```
期望:≥ 138 tests pass,0 fail。

- [ ] **Step 3: 重打 .app**

```bash
./scripts/make-app-bundle.sh debug
```

- [ ] **Step 4: dev harness 真实触发**

```bash
# 窗口 1:启 watcher
CAIRN_DEV_WATCH=1 build/Cairn.app/Contents/MacOS/CairnApp 2>&1 | tee /tmp/watcher.log

# 窗口 2:真实 Claude 会话触发
cd /some/test/project
claude      # 跑一段对话,比如"讲个笑话"

# 窗口 1 观察日志,应看到类似:
# [JSONLWatcher] started on /Users/sorain/.claude/projects
# [JSONLWatcher] discovered <uuid> at /Users/sorain/.claude/projects/-Users-sorain-.../session-<uuid>.jsonl
# [JSONLWatcher] +1 lines for <uuid> (from #1)
# [JSONLWatcher] +3 lines for <uuid> (from #2)
# ...
```

如果没看到 `+N lines`,诊断:
- `ls -la ~/.claude/projects/` 确认 Claude 确实在写
- `sqlite3 ~/Library/Application\ Support/Cairn/cairn.sqlite "SELECT * FROM sessions;"` 确认 session row 有写入
- 看 stderr 有无 `ingest failed`

---

### Task 13:用户验收清单

**Acceptance script**(用户执行):

```bash
# 1. 清状态,保证干净起点
sqlite3 "/Users/sorain/Library/Application Support/Cairn/cairn.sqlite" \
  "DELETE FROM sessions; DELETE FROM layout_states;"

# 2. 启动带 watcher 的 Cairn
CAIRN_DEV_WATCH=1 build/Cairn.app/Contents/MacOS/CairnApp 2>&1 | tee /tmp/watcher.log

# 3. 新开一个 terminal,跑一段 Claude 对话
cd /tmp && claude
# 问它:"讲三个笑话"

# 4. 回到 watcher 窗口,看 /tmp/watcher.log,应含:
#    [JSONLWatcher] started on ...
#    [JSONLWatcher] discovered <uuid> ...
#    [JSONLWatcher] +N lines for <uuid> (from #X)
#    (随着 Claude 输出多次出现 +N lines)

# 5. Cmd+Q Cairn

# 6. 磁盘取证:session 行应已入库
sqlite3 "/Users/sorain/Library/Application Support/Cairn/cairn.sqlite" \
  "SELECT id, jsonl_path, byte_offset, last_line_number FROM sessions;"
# 期望:有 ≥ 1 行,byte_offset > 0,last_line_number > 0

# 7. 重新启动 watcher,不起新 Claude 会话
CAIRN_DEV_WATCH=1 build/Cairn.app/Contents/MacOS/CairnApp 2>&1 | tee /tmp/watcher2.log
# 期望:在 /tmp/watcher2.log 看到 discovered 同一个 session,不再有 +N lines(因为文件没新增)
```

**验收项(5 项,用户回 ✅ / ❌):**

| # | 检查 | 期望 |
|---|---|---|
| 1 | 启动日志 | `[JSONLWatcher] started on ...` 出现一次 |
| 2 | 会话发现 | 跑 Claude 后 `[JSONLWatcher] discovered <uuid>` 日志出现 |
| 3 | 增量行流 | Claude 多轮对话时看到多条 `+N lines for <uuid>` |
| 4 | 磁盘持久化 | `sessions` 表行 `byte_offset > 0` & `last_line_number > 0` |
| 5 | 重启续读 | 第二次启动看到 discovered 但**不再**有 `+N lines`(文件无新内容时)|

---

## Known limitations(留给后续 milestone)

- **workspace 反推**:session 一律挂到 default workspace,M2.6 用 `system.cwd` / hash 反推分配到真实 workspace
- **session 生命周期**:watcher 不设 state 转换,只维护 `.live`;`.ended` / `.abandoned` / `.crashed` 的启发式检测留 M2.6
- **FSEvents 历史事件**:`kFSEventStreamEventIdSinceNow` 只看未来;历史 JSONL 靠 `scanExisting` 一次性加载,大量历史 session(500+)可能慢;M2.7 时加"懒加载 / 按需"
- **Cursor 写频率**:每 chunk 一次 upsert,200+ chunk/s 下 QPS 可能偏高;M2.7 视负载看是否合批
- **Cursor 丢最后一 chunk**:`SessionDAO.updateCursor` 走 async write,Cmd+Q 瞬间 await 被中断可能丢。下次启动 reconcile 会发现 file size > byteOffset,重新 ingest 已读过的行。上游消费者(M2.3 EventIngestor)必须对 events 做 idempotent(主键或 unique 约束),本 milestone 不处理
- **SwiftLog**:当前用 stderr 直写;M2.7 统一到 swift-log
- **UI**:watcher 事件没流入任何 UI 视图;Timeline 是 M2.4
- **API 调用顺序**:`events()` **必须先于** `start()` 调用(否则漏 `.discovered` 初始事件)。API 注释里强制。M2.3 接入时注意
- **`FSEventsWatcher` / `VnodeWatcher` 单订阅**:这两个组件的 `events()` 多次调用会覆盖 continuation;由于只被 JSONLWatcher 单持有,当前无问题。若 M2 后期需多订阅,迁到 `AsyncStream.makeStream` + continuations array

---

## 完成定义

全部 Task checkbox 打勾 + 用户 T13 回 ✅ + `git tag m2-1-done` 打在最终 commit + `docs/milestone-log.md` 追 M2.1 条目。
