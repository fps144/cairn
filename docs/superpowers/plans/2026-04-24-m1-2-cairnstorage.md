# M1.2 实施计划:CairnStorage(GRDB + 11 表 + migrator + DAO)

> **For agentic workers:** 本 plan 给 Claude 主导执行(见 `CLAUDE.md`)。每个 Task 按 Step 逐步完成;步骤用 checkbox(`- [ ]`)跟踪。用户职责仅 T15 验收。

**Goal:** 把 M1.1 的内存领域模型持久化到 SQLite:接入 GRDB 7.10.0,建 11 张表的 schema + migrator,为每个实体提供 DAO(CRUD),所有 DAO 对 M1.1 struct round-trip 保真。

**Architecture:** CairnStorage 封装 GRDB.DatabaseQueue(单连接 serial writer)为 actor,保证线程安全。`DatabaseMigrator` 声明式注册 v1 迁移,创建 11 张表 + 索引,插入 `schema_versions(1, ...)`。DAO 按实体分类(9 个具体 DAO + 1 个 settings),每个 DAO 实现 `upsert` / `fetch(id:)` / `fetchAll(...)` / `delete(id:)`,用显式列映射避免 Codable synthesis 的列名冲突(SQLite `snake_case` vs Swift `camelCase`)。

**Tech Stack:** Swift 6.3.1 toolchain · **swift-tools-version 5.9 不变**(SwiftPM 允许低 tools-version 包依赖高 tools-version 包,5.9 默认 Swift 5 模式正是我们想要的)· GRDB **7.10.0**(自身 Swift 6 严格模式,不影响调用方)· CairnCore(M1.1 已就绪)· XCTest in-memory DB。

**Claude 总耗时:** 约 150-240 分钟(1 个 session 能完成,但 context 偏紧,执行时注意 commit 频率)。
**用户总耗时:** 约 10 分钟(仅 T15 验收)。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. Package.swift 加 GRDB 7.10.0 依赖(tools-version 不改) | Claude | — |
| T2. Database actor + DatabaseConfiguration + 路径 | Claude | T1 |
| T3. DatabaseMigrator + v1 migration(11 表 + 索引 + schema_versions 插入)+ 迁移测试 | Claude | T2 |
| T4. Row 映射辅助(Date / UUID / enum → SQL TEXT 互转) | Claude | T3 |
| T5. WorkspaceDAO + CRUD 测试(≥ 5) | Claude | T4 |
| T6. SessionDAO + byte_offset 游标更新 + CRUD 测试(≥ 5) | Claude | T4 |
| T7. TaskDAO + task_sessions 关联表处理 + CRUD 测试(≥ 6) | Claude | T5, T6 |
| T8. EventDAO + 分页 + 配对查询 + CRUD 测试(≥ 6) | Claude | T6 |
| T9. BudgetDAO + state 枚举序列化 + CRUD 测试(≥ 5) | Claude | T7 |
| T10. PlanDAO + steps_json 序列化 + CRUD 测试(≥ 5) | Claude | T7 |
| T11. LayoutStateDAO + ApprovalDAO(v1.1 skeleton)+ SettingsDAO + 测试(≥ 6) | Claude | T4 |
| T12. swift build + swift test 全绿 验证(目标 ≥ 45 新测试) | Claude | T11 |
| T13. milestone-log + tag m1-2-done + push | Claude | T12 |
| T14. 占位清理:删除 M1.1 留的 Sources/CairnStorage/Storage.swift | Claude | T2 |
| T15. 验收清单(用户跑) | **用户** | T13 |

---

## 文件结构规划

**删除**:
- `Sources/CairnStorage/Storage.swift`(M1.1 占位,T14 清理)

**新建**:

```
Sources/CairnStorage/
├── CairnStorage.swift                    (namespace enum + scaffoldVersion)
├── Database.swift                        (actor,封装 DatabaseQueue)
├── DatabaseConfiguration.swift           (PRAGMA / 路径解析)
├── Schema/
│   ├── Migrations.swift                  (DatabaseMigrator + 注册 v1)
│   └── SchemaV1.swift                    (11 CREATE TABLE SQL + 索引 SQL)
├── DAOs/
│   ├── WorkspaceDAO.swift
│   ├── SessionDAO.swift
│   ├── TaskDAO.swift                     (含 task_sessions join 处理)
│   ├── EventDAO.swift
│   ├── BudgetDAO.swift
│   ├── PlanDAO.swift
│   ├── LayoutStateDAO.swift
│   ├── ApprovalDAO.swift                 (v1.1 skeleton)
│   └── SettingsDAO.swift
└── Support/
    └── Row+Mapping.swift                 (Row → UUID/Date/enum 辅助)

Tests/CairnStorageTests/
├── CairnStorageTests.swift               (smoke test)
├── MigrationTests.swift                  (v1 迁移应用 + schema_versions 插入)
├── WorkspaceDAOTests.swift
├── SessionDAOTests.swift
├── TaskDAOTests.swift
├── EventDAOTests.swift
├── BudgetDAOTests.swift
├── PlanDAOTests.swift
├── LayoutStateDAOTests.swift
├── ApprovalDAOTests.swift
└── SettingsDAOTests.swift
```

**修改**:

- `Package.swift` — tools-version 5.9 **不变**;加 GRDB 依赖;CairnStorage target 加 GRDB 依赖;新增 CairnStorageTests target
- `Sources/CairnCore/CairnCore.swift` — 版本 bump 0.1.0-m1.1 → 0.2.0-m1.2
- `Tests/CairnCoreTests/CairnCoreTests.swift` — 版本断言 `m1.1` → `m1.2`
- `docs/milestone-log.md` — T13 追加 M1.2 完成条目

---

## 设计决策(pinned,Plan 执行中不重新讨论)

| # | 决策 | 选择 | 理由 |
|---|---|---|---|
| 1 | swift-tools-version | **不 bump,保持 5.9** | SwiftPM 规则:每个 Package.swift 用自己的 tools-version 独立解析,A(低)可依赖 B(高),只要 toolchain ≥ max。本机 Swift 6.3.1 能解析 GRDB 的 6.1 manifest,无需升。若 `swift package resolve` 意外抱怨,fallback 升 6.1(一行改)。Spec v1 决策 A2 只约束 "SPM 多模块",未锁 tools-version |
| 2 | 目标语言模式 | **无需显式声明**(5.9 默认 Swift 5) | tools-version 5.9 下,所有 target 默认 Swift 5 模式 —— 正是我们想要的(避 Swift 6 严格并发)。GRDB 自身在其 Swift 6 模式下编译,ABI 层面可被 Swift 5 代码 import,无缝使用。M4.1 后若要升 Swift 6,再 bump tools-version 到 6.0+ 并显式 `.swiftLanguageMode()` |
| 3 | GRDB DatabaseQueue vs Pool | **DatabaseQueue**(单连接 serial writer) | Cairn 桌面单进程,写操作远少于读;DatabaseQueue 的 serial writer 语义最接近 spec §3.4 "GRDB 内置 serial writer";Pool 的多读并发留 v1.5 若有瓶颈再切 |
| 4 | Database 访问隔离 | **actor Database** | spec §3.4 说 "GRDB DAO 内置 serial writer 在 DB 内部";我们把 Database 本身也设为 actor,让调用方 `await db.read/write` 显式跨隔离域。Swift 5 模式下 actor 仍完全可用(async/await/actor 是 5.5+) |
| 5 | Date 持久化格式 | **ISO-8601 TEXT**(不是 GRDB 默认的 double 秒数) | spec §7.2 硬要求 "时间列一律 ISO-8601 字符串";与 M1.1 `CairnCore.jsonEncoder` 策略一致;跨工具(`sqlite3 .dump`)可读 |
| 6 | UUID 持久化格式 | **`.uuidString` TEXT** | 与 spec §D `id TEXT PRIMARY KEY` 匹配;SQLite 无原生 UUID 类型 |
| 7 | State enum 持久化 | **rawValue TEXT** | M1.1 所有 enum 已是 `String` raw value;直接存;查询 `WHERE state = 'live'` 可读 |
| 8 | Event.rawPayloadJson 持久化 | **TEXT 存原始 JSON 字符串** | M1.1 已决定 String?,SQLite TEXT 对应;spec §7.4 "90 天后置 NULL 归档"留 M4.3 |
| 9 | DAO 映射方式 | **手写 `from(row:)` / `toArguments()`**,不用 GRDB Codable `FetchableRecord/PersistableRecord` 自动 | 列名 `snake_case` vs Swift `camelCase` 不一致;GRDB Codable 自动合成依赖 CodingKeys,会绕开 M1.1 的 JSON 策略。手写虽啰嗦但精确可控,测试覆盖保障保真 |
| 10 | Plan.steps 持久化 | **`steps_json` 列存 JSON 字符串** | spec §D `plans.steps_json TEXT NOT NULL`;用 `CairnCore.jsonEncoder`(ISO-8601)序列化 `[PlanStep]` |
| 11 | CairnTask.sessionIds 持久化 | **`task_sessions` 关联表,不在 tasks 行里存** | spec §D 明确有 `task_sessions` 表;TaskDAO `save(task)` 内部先 INSERT/UPDATE tasks 行,再删除该 task 所有 task_sessions 行,按当前 `sessionIds` 重新插入 |

---

## Spec §D schema 调和说明

spec §2.6 的 Swift pseudocode schema 和 §D 的 SQLite schema 在**字段数量 / 命名 / 类型**上有若干不一致。本 plan 在 **§D 为准**(§D 是硬 SQL,§2.6 是概念示意),T3 migration 按 §D 精确复制。已知不一致:

| 位置 | §2.6 pseudocode | §D SQLite | 取向 |
|---|---|---|---|
| Budget `updatedAt` | 未列出 | `updated_at TIMESTAMP NOT NULL` | M1.1 已跟 §D(Budget struct 含 updatedAt) |
| Budget wallSeconds | `maxWallTime` / `usedWallTime` | `max_wall_seconds` / `used_wall_seconds` | M1.1 struct 用 `maxWallSeconds` / `usedWallSeconds`,与 §D 一致 |
| Session 实体 | 含 `isImported: Bool` | **§D 无此列** | **补**:T3 v1 migration 加 `is_imported INTEGER NOT NULL DEFAULT 0`(§2.6 + M1.1 struct 有) |
| tasks 表 FK CASCADE | §2.6 未说 | `workspace_id REFERENCES workspaces(id)`(无 ON DELETE CASCADE)| 按 §D 原样(workspace 归档/删除不自动连带删 tasks,保留审计价值) |

**补充列清单**(migration 必须补进 v1):
- `sessions.is_imported INTEGER NOT NULL DEFAULT 0`

**其他 §D 可能误差或需要验证**:
- `events.summary` 文本长度无 CHECK 约束(spec §2.6 ≤ 200 字是软约束,v1 不在 SQL 层强制,应用层保证)

---

## 架构硬约束(不得违反)

- **CairnStorage → 只 import CairnCore + GRDB**,不得 import CairnClaude / CairnServices / CairnUI / CairnApp(spec §3.2)
- CairnCore **不得** import CairnStorage(已在 M1.1 强制,CairnStorage 依赖方向单向)
- `Database` actor 的**唯一**公开 API:`read(_:)` 和 `write(_:)` 闭包;不暴露 `DatabaseQueue` 原生类型
- DAO 方法**全 async**(因为要 `await db.read/write`);调用方在 actor 或 async 上下文使用
- 测试用 **in-memory DB**(`DatabaseLocation.inMemory` → GRDB `DatabaseQueue(path: ":memory:")`),每个测试独立实例,不依赖文件系统

---

## T1:Package.swift 加 GRDB 7.10.0 依赖(tools-version 不改)

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1:完全替换 Package.swift**

用 Edit/Write 工具把 `Package.swift` 内容替换为:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cairn",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CairnApp", targets: ["CairnApp"]),
        .library(name: "CairnCore", targets: ["CairnCore"]),
        .library(name: "CairnStorage", targets: ["CairnStorage"]),
        .library(name: "CairnClaude", targets: ["CairnClaude"]),
        .library(name: "CairnTerminal", targets: ["CairnTerminal"]),
        .library(name: "CairnServices", targets: ["CairnServices"]),
        .library(name: "CairnUI", targets: ["CairnUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.10.0"),
    ],
    targets: [
        .target(name: "CairnCore"),
        .target(
            name: "CairnStorage",
            dependencies: [
                "CairnCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(name: "CairnClaude", dependencies: ["CairnCore", "CairnStorage"]),
        .target(
            name: "CairnTerminal",
            dependencies: [
                "CairnCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .target(name: "CairnServices", dependencies: ["CairnCore", "CairnStorage", "CairnClaude"]),
        .target(name: "CairnUI", dependencies: ["CairnServices", "CairnTerminal"]),
        .executableTarget(name: "CairnApp", dependencies: ["CairnUI"]),
        .testTarget(name: "CairnCoreTests", dependencies: ["CairnCore"]),
        .testTarget(name: "CairnStorageTests", dependencies: ["CairnStorage"]),
    ]
)
```

**变更点**(相对 M1.1 Package.swift):
1. `// swift-tools-version:5.9` **不变**
2. 加 GRDB 依赖:`.package(url: "https://github.com/groue/GRDB.swift", from: "7.10.0")`
3. CairnStorage target 加 `.product(name: "GRDB", package: "GRDB.swift")` 依赖
4. 新增 `.testTarget(name: "CairnStorageTests", dependencies: ["CairnStorage"])`

**没做**的事(和初版 plan 不同):
- 不升 tools-version(SwiftPM 允许 5.9 manifest 依赖 6.1 manifest,不需升)
- 不加 per-target `.swiftLanguageMode(.v5)`(tools 5.9 下默认就是 Swift 5,显式声明反而混淆)

- [ ] **Step 2:swift package resolve 验证 GRDB 拉取**

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift package resolve 2>&1 | tail -10
```

**Expected**:`Fetching https://github.com/groue/GRDB.swift` + `Computed at 7.10.x` + 无错。

**失败排查**:
- **"package requires swift-tools-version 6.1"**(罕见,SwiftPM 规则允许低依赖高,但若真命中):用 Edit 把 `// swift-tools-version:5.9` 改为 `// swift-tools-version:6.1`,重跑。**此时需加** per-target `.swiftLanguageMode(.v5)` 以保持 Swift 5 语义(tools 6.0+ 默认变 Swift 6 严格并发,会触发 M1.1 未审计的 Sendable 边界错误)
- 网络超时:重试,或检查 GitHub 连通性
- 符号冲突:GRDB 带 `SQLite3` 符号,若和其他库冲突会报 duplicate symbol,但 M1.2 无其他 SQLite 库

- [ ] **Step 3:swift build 验证全部 target 可编译**

```bash
swift build 2>&1 | tail -8
```

**Expected**:`Build complete!`。GRDB 首次编译可能需 60-120s。

**失败排查**:
- 若 CairnCore / CairnUI 等无 GRDB 使用的 target 编译失败,检查它们的 `swiftSettings: v5` 是否遗漏
- 若 CairnStorage 编译失败报 `Cannot find 'GRDB' in scope`,检查 Sources/CairnStorage 里是否已有文件 `import GRDB`(还没加,这一步只验证骨架)

- [ ] **Step 4:swift test 验证旧测试未受影响**

```bash
swift test 2>&1 | tail -5
```

**Expected**:`Executed 54 tests, with 0 failures`(M1.1 的 54 个)。

- [ ] **Step 5:Commit(Package.resolved 同时更新)**

```bash
git add Package.swift Package.resolved
git commit -m "build: GRDB 7.10.0 依赖(tools-version 5.9 不变)

SwiftPM 允许 tools 5.9 的 Cairn 依赖 tools 6.1 的 GRDB —— 各 manifest
独立解析,本机 Swift 6.3.1 可处理。Cairn target 隐式 Swift 5 模式
(5.9 默认),GRDB 在自身 Swift 6 模式编译,ABI 层可被 Cairn 无缝 import。
Package.resolved 锁定 GRDB 7.10.x 的精确 commit。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T2:Database actor + DatabaseConfiguration

**Files:**
- Create: `Sources/CairnStorage/CairnStorage.swift`(替换 M1.1 占位 Storage.swift)
- Create: `Sources/CairnStorage/Database.swift`
- Create: `Sources/CairnStorage/DatabaseConfiguration.swift`
- Create: `Tests/CairnStorageTests/CairnStorageTests.swift`

- [ ] **Step 1:写 CairnStorage 命名空间**

`Sources/CairnStorage/CairnStorage.swift`:

```swift
import Foundation
import CairnCore

/// Cairn 存储层命名空间。封装 GRDB,对外暴露 `Database` actor + 各 DAO。
///
/// spec §3.2:CairnStorage 只依赖 CairnCore + GRDB。
/// 本模块不暴露 GRDB 原生类型给上层(Services / UI)。
public enum CairnStorage {
    public static let scaffoldVersion = CairnCore.scaffoldVersion
}
```

- [ ] **Step 2:写 DatabaseConfiguration**

`Sources/CairnStorage/DatabaseConfiguration.swift`:

```swift
import Foundation
import GRDB

/// 数据库配置 + 路径解析。spec §7.1 / §7.8。
public enum DatabaseLocation {
    /// 生产路径:`~/Library/Application Support/Cairn/cairn.sqlite`
    case productionSupportDirectory
    /// 给定绝对路径
    case path(String)
    /// 内存 DB(测试用)
    case inMemory

    /// 解析为可直接传给 GRDB 的参数。
    public func resolve() throws -> DatabasePath {
        switch self {
        case .productionSupportDirectory:
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let cairnDir = appSupport.appendingPathComponent("Cairn", isDirectory: true)
            try FileManager.default.createDirectory(
                at: cairnDir, withIntermediateDirectories: true
            )
            return .file(cairnDir.appendingPathComponent("cairn.sqlite").path)
        case .path(let p):
            return .file(p)
        case .inMemory:
            return .inMemory
        }
    }
}

/// 已解析的路径(file 或 in-memory)。
public enum DatabasePath {
    case file(String)
    case inMemory
}

/// 构造 GRDB 的 Configuration,含 spec §7.8 要求的 PRAGMA。
public func makeCairnDatabaseConfiguration() -> Configuration {
    var config = Configuration()
    // spec §7.8 性能纪律
    config.prepareDatabase { db in
        // cache_size 负数表示 KB(-64000 = 64 MB page cache)
        try db.execute(sql: "PRAGMA cache_size = -64000;")
        // 外键 ON DELETE CASCADE 生效必须启
        try db.execute(sql: "PRAGMA foreign_keys = ON;")
    }
    // WAL 模式 + synchronous=NORMAL 在 DatabaseMigrator 第一次写入时已默认;
    // GRDB 对 DatabaseQueue 默认 journal_mode=wal(v5+),synchronous=NORMAL 按需设。
    return config
}
```

**注**:GRDB 7+ 对 `DatabaseQueue` 默认启用 WAL。`synchronous` 默认 FULL,为性能降 NORMAL 可在 `prepareDatabase` 内加 `try db.execute(sql: "PRAGMA synchronous = NORMAL;")`。M1.2 不加此 PRAGMA(avoid pre-optimization,M4.3 若性能测试不达标再加)。

- [ ] **Step 3:写 Database actor**

`Sources/CairnStorage/Database.swift`:

```swift
import Foundation
import GRDB

/// Cairn 数据库入口。actor 隔离所有 DB 访问。
///
/// 公开 API 只有 `read(_:)` / `write(_:)` 两个闭包形式。
/// DAO 通过注入 `Database` 实例,在闭包内拿 `GRDB.Database` 做 CRUD。
public actor CairnDatabase {
    private let queue: DatabaseQueue

    /// 按 location 打开数据库并应用 migrator。
    public init(
        location: DatabaseLocation,
        migrator: DatabaseMigrator
    ) async throws {
        let path = try location.resolve()
        let config = makeCairnDatabaseConfiguration()
        self.queue = try {
            switch path {
            case .file(let p):
                return try DatabaseQueue(path: p, configuration: config)
            case .inMemory:
                // 用 SQLite 特殊路径 ":memory:" 显式指定内存 DB,
                // 不依赖 GRDB 是否存在 DatabaseQueue(configuration:) 的无参签名。
                return try DatabaseQueue(path: ":memory:", configuration: config)
            }
        }()
        // 同步 migrator(DatabaseQueue.write 是 sync,migrator.migrate 内部处理)
        try migrator.migrate(queue)
    }

    /// 只读闭包。DAO 可并发读(GRDB queue 内部序列化)。
    public func read<T: Sendable>(
        _ body: @Sendable (GRDB.Database) throws -> T
    ) async throws -> T {
        try queue.read(body)
    }

    /// 写入闭包(含隐式事务)。闭包抛错则回滚。
    public func write<T: Sendable>(
        _ body: @Sendable (GRDB.Database) throws -> T
    ) async throws -> T {
        try queue.write(body)
    }
}
```

- [ ] **Step 4:写 smoke 测试**

`Tests/CairnStorageTests/CairnStorageTests.swift`:

```swift
import XCTest
import GRDB
@testable import CairnStorage

final class CairnStorageTests: XCTestCase {
    func test_scaffoldVersion_matchesCore() {
        // CairnStorage.scaffoldVersion 与 CairnCore.scaffoldVersion 相等
        XCTAssertEqual(CairnStorage.scaffoldVersion,
                       "0.2.0-m1.2",
                       "M1.2 应 bump 到 0.2.0-m1.2,见设计决策")
    }

    func test_inMemoryDatabase_opensAndClosesCleanly() async throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("noop") { db in
            try db.execute(sql: "CREATE TABLE test (id INTEGER)")
        }
        let db = try await CairnDatabase(location: .inMemory, migrator: migrator)
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM test") ?? -1
        }
        XCTAssertEqual(count, 0)
    }
}
```

**注**:此处 `CairnStorage.scaffoldVersion` 期望 `"0.2.0-m1.2"` —— 但 M1.1 设置的是 `CairnCore.scaffoldVersion = "0.1.0-m1.1"`,且 CairnStorage.scaffoldVersion 直接 = CairnCore.scaffoldVersion。所以 T2 同时要在 CairnCore 里 bump 到 `"0.2.0-m1.2"`。

- [ ] **Step 5:bump CairnCore scaffoldVersion 到 m1.2**

用 Edit 工具把 `Sources/CairnCore/CairnCore.swift` 里的 `"0.1.0-m1.1"` 替换为 `"0.2.0-m1.2"`。

同步更新 `Tests/CairnCoreTests/CairnCoreTests.swift` 里的 `"m1.1"` 为 `"m1.2"`(两处:断言 + 失败消息)。

- [ ] **Step 6:删除 M1.1 的占位 Storage.swift**

```bash
rm /Users/sorain/xiaomi_projects/AICoding/cairn/Sources/CairnStorage/Storage.swift
```

- [ ] **Step 7:`swift build` 确认仍编译**

```bash
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`。

**注**:T3 还没完成,`CairnStorageTests::test_inMemoryDatabase_opensAndClosesCleanly` 目前能过(只用 noop migrator)。

- [ ] **Step 8:`swift test --filter CairnStorageTests` 验证**

```bash
swift test --filter CairnStorageTests 2>&1 | tail -5
```

**Expected**:`Executed 2 tests, with 0 failures`。

- [ ] **Step 9:Commit**

```bash
git add Sources/CairnStorage/ Sources/CairnCore/CairnCore.swift \
        Tests/CairnStorageTests/ Tests/CairnCoreTests/CairnCoreTests.swift
git commit -m "feat(storage): CairnDatabase actor + DatabaseConfiguration + 2 smoke 测试

删除 M1.1 占位 Storage.swift;新建 CairnStorage.swift 命名空间(scaffoldVersion
跟随 CairnCore bump 到 0.2.0-m1.2)。
Database 封装 DatabaseQueue 为 actor,只暴露 read/write 闭包;
DatabaseLocation 支持生产路径 / 绝对路径 / 内存(测试用)。
配置含 cache_size=-64000 + foreign_keys=ON(spec §7.8);
synchronous=NORMAL 留 M4.3 按需启用。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T3:DatabaseMigrator + v1 migration(11 表 + 索引)+ 迁移测试

**Files:**
- Create: `Sources/CairnStorage/Schema/Migrations.swift`
- Create: `Sources/CairnStorage/Schema/SchemaV1.swift`
- Create: `Tests/CairnStorageTests/MigrationTests.swift`

- [ ] **Step 1:写 MigrationTests(红灯)**

`Tests/CairnStorageTests/MigrationTests.swift`:

```swift
import XCTest
import GRDB
@testable import CairnStorage

final class MigrationTests: XCTestCase {
    func test_v1Migration_createsAll11Tables() async throws {
        let db = try await makeInMemoryDatabase()
        let tables = try await db.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type='table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
                """)
        }
        let expected = [
            "approvals",
            "budgets",
            "events",
            "layout_states",
            "plans",
            "schema_versions",
            "sessions",
            "settings",
            "task_sessions",
            "tasks",
            "workspaces",
        ]
        XCTAssertEqual(tables, expected,
                       "v1 迁移应创建 spec §D 的全部 11 张表")
    }

    func test_v1Migration_insertsSchemaVersionsRow() async throws {
        let db = try await makeInMemoryDatabase()
        let version = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT version FROM schema_versions WHERE version = 1")
        }
        XCTAssertEqual(version, 1, "schema_versions 应含 v1 行")
    }

    func test_v1Migration_foreignKeysEnabled() async throws {
        let db = try await makeInMemoryDatabase()
        let fkEnabled = try await db.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
        }
        XCTAssertEqual(fkEnabled, 1, "foreign_keys PRAGMA 应启用(设计决策 #PRAGMA)")
    }

    func test_v1Migration_isIdempotent() async throws {
        // 重复 open 同一内存 DB 不合理(每次 new instance),
        // 但我们可以跑相同 migrator 两次,确认 GRDB 幂等。
        // GRDB DatabaseMigrator 内置幂等性(通过 grdb_migrations 表记录)。
        var migrator = CairnStorage.makeMigrator()
        let queue = try DatabaseQueue(path: ":memory:")
        try migrator.migrate(queue)
        try migrator.migrate(queue)  // 第二次不应 throw
        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_versions") ?? 0
        }
        XCTAssertEqual(count, 1, "重复 migrate 不应重复插入 schema_versions")
    }

    // MARK: - Helper
    private func makeInMemoryDatabase() async throws -> CairnDatabase {
        try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter MigrationTests 2>&1 | tail -10
```

**Expected**:编译错 `Cannot find 'makeMigrator' in scope`。

- [ ] **Step 3:写 SchemaV1.swift(纯 SQL 常量)**

`Sources/CairnStorage/Schema/SchemaV1.swift`(内容完整照 spec §D,补 sessions.is_imported):

```swift
import Foundation

/// v1 schema 的 CREATE TABLE + CREATE INDEX SQL。
/// 严格对齐 spec §D,补 spec §2.6 / M1.1 struct 的 `sessions.is_imported` 列。
enum SchemaV1 {
    /// 所有 DDL,按 FK 依赖顺序排列。
    static let statements: [String] = [
        // workspaces(无 FK)
        """
        CREATE TABLE workspaces (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            cwd TEXT NOT NULL UNIQUE,
            created_at TIMESTAMP NOT NULL,
            last_active_at TIMESTAMP NOT NULL,
            archived_at TIMESTAMP
        )
        """,

        // sessions(依赖 workspaces)
        """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
            jsonl_path TEXT NOT NULL,
            byte_offset INTEGER DEFAULT 0,
            last_line_number INTEGER DEFAULT 0,
            started_at TIMESTAMP NOT NULL,
            ended_at TIMESTAMP,
            state TEXT NOT NULL,
            model_used TEXT,
            is_imported INTEGER NOT NULL DEFAULT 0
        )
        """,
        "CREATE INDEX idx_sessions_workspace ON sessions(workspace_id)",
        "CREATE INDEX idx_sessions_state ON sessions(state) WHERE state IN ('live','idle')",

        // tasks(依赖 workspaces)
        """
        CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id),
            title TEXT NOT NULL,
            intent TEXT,
            status TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL,
            updated_at TIMESTAMP NOT NULL,
            completed_at TIMESTAMP
        )
        """,
        "CREATE INDEX idx_tasks_workspace_status ON tasks(workspace_id, status)",

        // task_sessions(join,依赖 tasks + sessions)
        """
        CREATE TABLE task_sessions (
            task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
            session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE,
            attached_at TIMESTAMP NOT NULL,
            PRIMARY KEY (task_id, session_id)
        )
        """,

        // events(依赖 sessions)
        """
        CREATE TABLE events (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            type TEXT NOT NULL,
            category TEXT,
            tool_name TEXT,
            tool_use_id TEXT,
            paired_event_id TEXT,
            timestamp TIMESTAMP NOT NULL,
            line_number INTEGER NOT NULL,
            block_index INTEGER DEFAULT 0,
            summary TEXT NOT NULL,
            raw_payload_json TEXT,
            byte_offset_in_jsonl INTEGER
        )
        """,
        "CREATE INDEX idx_events_session_seq ON events(session_id, line_number, block_index)",
        "CREATE INDEX idx_events_tool_use_id ON events(tool_use_id) WHERE tool_use_id IS NOT NULL",
        "CREATE INDEX idx_events_type ON events(session_id, type)",

        // budgets(依赖 tasks)
        """
        CREATE TABLE budgets (
            task_id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE,
            max_input_tokens INTEGER,
            max_output_tokens INTEGER,
            max_cost_usd REAL,
            max_wall_seconds INTEGER,
            used_input_tokens INTEGER DEFAULT 0,
            used_output_tokens INTEGER DEFAULT 0,
            used_cost_usd REAL DEFAULT 0,
            used_wall_seconds INTEGER DEFAULT 0,
            state TEXT DEFAULT 'normal',
            updated_at TIMESTAMP NOT NULL
        )
        """,

        // plans(依赖 tasks)
        """
        CREATE TABLE plans (
            id TEXT PRIMARY KEY,
            task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            source TEXT NOT NULL,
            steps_json TEXT NOT NULL,
            markdown_raw TEXT,
            updated_at TIMESTAMP NOT NULL
        )
        """,
        "CREATE INDEX idx_plans_task ON plans(task_id, updated_at DESC)",

        // layout_states(依赖 workspaces)
        """
        CREATE TABLE layout_states (
            workspace_id TEXT PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
            layout_json TEXT NOT NULL,
            updated_at TIMESTAMP NOT NULL
        )
        """,

        // approvals(v1.1,FK 不 CASCADE)
        """
        CREATE TABLE approvals (
            id TEXT PRIMARY KEY,
            session_id TEXT REFERENCES sessions(id),
            tool_name TEXT NOT NULL,
            tool_input_json TEXT NOT NULL,
            decision TEXT NOT NULL,
            decided_by TEXT NOT NULL,
            decided_at TIMESTAMP NOT NULL,
            reason TEXT
        )
        """,

        // settings(无 FK)
        """
        CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL,
            updated_at TIMESTAMP NOT NULL
        )
        """,

        // schema_versions(无 FK,migrator 填)
        """
        CREATE TABLE schema_versions (
            version INTEGER PRIMARY KEY,
            applied_at TIMESTAMP NOT NULL,
            description TEXT
        )
        """,
    ]
}
```

- [ ] **Step 4:写 Migrations.swift**

`Sources/CairnStorage/Schema/Migrations.swift`:

```swift
import Foundation
import GRDB

extension CairnStorage {
    /// 构造 Cairn 主数据库的 migrator。包含 v1 schema。
    public static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            for sql in SchemaV1.statements {
                try db.execute(sql: sql)
            }
            // 写入 schema_versions 行
            try db.execute(
                sql: """
                    INSERT INTO schema_versions (version, applied_at, description)
                    VALUES (?, ?, ?)
                """,
                arguments: [1, ISO8601DateFormatter().string(from: Date()),
                            "v1.0 initial schema (11 tables)"]
            )
        }

        return migrator
    }
}
```

- [ ] **Step 5:跑测试确认绿**

```bash
swift test --filter MigrationTests 2>&1 | tail -10
```

**Expected**:`Executed 4 tests, with 0 failures`。

- [ ] **Step 6:Commit**

```bash
git add Sources/CairnStorage/Schema/ Tests/CairnStorageTests/MigrationTests.swift
git commit -m "feat(storage): DatabaseMigrator + v1 schema(11 表 + 索引)+ 4 测试

SchemaV1.statements 常量数组严格对齐 spec §D,补 sessions.is_imported
(§2.6 / M1.1 struct 有此字段但 §D 遗漏)。
CairnStorage.makeMigrator() 注册 v1_initial_schema migration,
运行后 schema_versions 插入 (1, now, 'v1.0 initial schema')。
GRDB DatabaseMigrator 内置幂等性,test_v1Migration_isIdempotent 验证。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T4:Row 映射辅助(Date / UUID / enum → SQL TEXT 互转)

**Files:**
- Create: `Sources/CairnStorage/Support/Row+Mapping.swift`

**注**:此 task 是后续 DAO 的共享工具,不新增公开测试(由 DAO 测试覆盖间接验证)。

- [ ] **Step 1:写辅助函数**

`Sources/CairnStorage/Support/Row+Mapping.swift`:

```swift
import Foundation
import GRDB
import CairnCore

// MARK: - UUID ↔ DatabaseValue

/// GRDB 7 未内置 UUID 的 DatabaseValueConvertible 支持。
/// 此扩展补齐,用 `.uuidString` 作为 TEXT 列存取格式,
/// 配合 spec §D 的 `id TEXT PRIMARY KEY` 定义。
/// 加这个扩展后,`UUID.fetchAll(db, sql: ...)` / `UUID.fetchOne(...)` 等 GRDB
/// fetch 静态方法可直接在 UUID 上使用。
extension UUID: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        uuidString.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> UUID? {
        String.fromDatabaseValue(dbValue).flatMap(UUID.init(uuidString:))
    }
}

// MARK: - ISO-8601 共享 formatter

enum ISO8601 {
    /// 与 CairnCore.jsonEncoder 同一策略。
    /// ISO8601DateFormatter 是 thread-safe(官方文档确认)。
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) throws -> Date {
        guard let date = formatter.date(from: string) else {
            throw DatabaseError.invalidDateFormat(string)
        }
        return date
    }
}

// MARK: - Row 取值扩展

extension Row {
    /// 取 TEXT 列并解析为 UUID。列不存在或不是有效 UUID 抛错。
    func uuid(_ column: String) throws -> UUID {
        let str: String = try decode(column: column)
        guard let uuid = UUID(uuidString: str) else {
            throw DatabaseError.invalidUUID(str, column: column)
        }
        return uuid
    }

    func uuidIfPresent(_ column: String) throws -> UUID? {
        let str: String? = self[column]
        guard let str else { return nil }
        guard let uuid = UUID(uuidString: str) else {
            throw DatabaseError.invalidUUID(str, column: column)
        }
        return uuid
    }

    /// 取 TEXT 列并解析为 Date(ISO-8601)。
    func date(_ column: String) throws -> Date {
        let str: String = try decode(column: column)
        return try ISO8601.date(from: str)
    }

    func dateIfPresent(_ column: String) throws -> Date? {
        let str: String? = self[column]
        guard let str else { return nil }
        return try ISO8601.date(from: str)
    }

    /// 取 TEXT 列并转为给定 RawRepresentable(State enum 等)。
    func rawEnum<T: RawRepresentable>(_ column: String, as type: T.Type) throws -> T
    where T.RawValue == String {
        let raw: String = try decode(column: column)
        guard let val = T(rawValue: raw) else {
            throw DatabaseError.invalidEnumRawValue(raw, column: column)
        }
        return val
    }

    // MARK: - 泛型 helper

    private func decode<T>(column: String) throws -> T where T: DatabaseValueConvertible {
        guard let val: T = self[column] else {
            throw DatabaseError.missingColumn(column)
        }
        return val
    }
}

// MARK: - Cairn 专用错误

public enum DatabaseError: Error, Equatable {
    case missingColumn(String)
    case invalidUUID(String, column: String)
    case invalidDateFormat(String)
    case invalidEnumRawValue(String, column: String)
}
```

- [ ] **Step 2:swift build 验证编译通过**

```bash
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`。

- [ ] **Step 3:Commit**

```bash
git add Sources/CairnStorage/Support/
git commit -m "feat(storage): Row 映射辅助 + DatabaseError

ISO-8601 Date / UUID / RawRepresentable enum 的 Row 解码扩展,
为后续 9 个 DAO 共享。DatabaseError 枚举覆盖 4 类映射错误,
Equatable 便于测试断言。ISO8601DateFormatter 单例线程安全(官方确认)。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T5:WorkspaceDAO + CRUD 测试

**Files:**
- Create: `Sources/CairnStorage/DAOs/WorkspaceDAO.swift`
- Create: `Tests/CairnStorageTests/WorkspaceDAOTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnStorageTests/WorkspaceDAOTests.swift`:

```swift
import XCTest
import CairnCore
@testable import CairnStorage

final class WorkspaceDAOTests: XCTestCase {
    private var db: CairnDatabase!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
    }

    func test_upsert_insertsNewRow() async throws {
        let ws = Workspace(name: "Cairn", cwd: "/Users/sorain/cairn")
        try await WorkspaceDAO.upsert(ws, in: db)
        let fetched = try await WorkspaceDAO.fetch(id: ws.id, in: db)
        XCTAssertEqual(fetched, ws)
    }

    func test_upsert_updatesExistingRow() async throws {
        let id = UUID()
        let v1 = Workspace(id: id, name: "v1", cwd: "/tmp/v1")
        try await WorkspaceDAO.upsert(v1, in: db)
        let v2 = Workspace(
            id: id, name: "v2", cwd: "/tmp/v2",
            createdAt: v1.createdAt,
            lastActiveAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        try await WorkspaceDAO.upsert(v2, in: db)
        let fetched = try await WorkspaceDAO.fetch(id: id, in: db)
        XCTAssertEqual(fetched, v2)
    }

    func test_fetch_returnsNilForMissing() async throws {
        let fetched = try await WorkspaceDAO.fetch(id: UUID(), in: db)
        XCTAssertNil(fetched)
    }

    func test_fetchAll_ordersByLastActiveDesc() async throws {
        let older = Workspace(
            name: "Old", cwd: "/a",
            lastActiveAt: Date(timeIntervalSince1970: 1_000_000_000)
        )
        let newer = Workspace(
            name: "New", cwd: "/b",
            lastActiveAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        try await WorkspaceDAO.upsert(older, in: db)
        try await WorkspaceDAO.upsert(newer, in: db)
        let all = try await WorkspaceDAO.fetchAll(in: db)
        XCTAssertEqual(all.map(\.name), ["New", "Old"])
    }

    func test_delete_removesRow() async throws {
        let ws = Workspace(name: "X", cwd: "/x")
        try await WorkspaceDAO.upsert(ws, in: db)
        try await WorkspaceDAO.delete(id: ws.id, in: db)
        let fetched = try await WorkspaceDAO.fetch(id: ws.id, in: db)
        XCTAssertNil(fetched)
    }

    func test_uniqueCwd_constraint() async throws {
        // spec §D: workspaces.cwd UNIQUE
        let a = Workspace(name: "A", cwd: "/shared")
        let b = Workspace(name: "B", cwd: "/shared")
        try await WorkspaceDAO.upsert(a, in: db)
        do {
            try await WorkspaceDAO.upsert(b, in: db)
            XCTFail("应该抛 UNIQUE 约束错")
        } catch {
            // GRDB 把 SQLite error 封装为 DatabaseError;任何 Error 都算验证通过
        }
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter WorkspaceDAOTests 2>&1 | tail -5
```

**Expected**:编译错 `Cannot find 'WorkspaceDAO' in scope`。

- [ ] **Step 3:写 WorkspaceDAO**

`Sources/CairnStorage/DAOs/WorkspaceDAO.swift`:

```swift
import Foundation
import GRDB
import CairnCore

/// Workspace 实体的 SQLite CRUD。
/// 所有方法 async,内部走 `CairnDatabase.read/write`。
public enum WorkspaceDAO {
    /// INSERT OR REPLACE(upsert 语义)。
    public static func upsert(_ ws: Workspace, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO workspaces
                    (id, name, cwd, created_at, last_active_at, archived_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    ws.id.uuidString,
                    ws.name,
                    ws.cwd,
                    ISO8601.string(from: ws.createdAt),
                    ISO8601.string(from: ws.lastActiveAt),
                    ws.archivedAt.map(ISO8601.string(from:)),
                ]
            )
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> Workspace? {
        try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM workspaces WHERE id = ?",
                arguments: [id.uuidString]
            ).map { try Self.make(from: $0) }
        }
    }

    public static func fetchAll(in db: CairnDatabase) async throws -> [Workspace] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM workspaces ORDER BY last_active_at DESC"
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    public static func delete(id: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM workspaces WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Row mapping

    private static func make(from row: Row) throws -> Workspace {
        Workspace(
            id: try row.uuid("id"),
            name: row\["name"],
            cwd: row\["cwd"],
            createdAt: try row.date("created_at"),
            lastActiveAt: try row.date("last_active_at"),
            archivedAt: try row.dateIfPresent("archived_at")
        )
    }
}
```

**注**:`row\["name"]` 依赖 GRDB 的 `Row.subscript<V>(column)`;对非 Optional `V`,不存在会返回 `nil` 导致 Row 解包失败。更严格的写法是用 T4 的 `decode` helper,但 GRDB 的 subscript 对 NOT NULL 列足够用。此处简化。

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter WorkspaceDAOTests 2>&1 | tail -5
```

**Expected**:`Executed 6 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnStorage/DAOs/WorkspaceDAO.swift Tests/CairnStorageTests/WorkspaceDAOTests.swift
git commit -m "feat(storage): WorkspaceDAO + 6 CRUD 测试

INSERT OR REPLACE 实现 upsert 语义;fetch/fetchAll/delete 配套。
fetchAll 按 last_active_at DESC 排序(spec §6.2 sidebar 展示需求)。
测试覆盖 insert / update / missing / sort / delete / UNIQUE(cwd)约束。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T6:SessionDAO + byte_offset 游标更新 + CRUD 测试

**Files:**
- Create: `Sources/CairnStorage/DAOs/SessionDAO.swift`
- Create: `Tests/CairnStorageTests/SessionDAOTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnStorageTests/SessionDAOTests.swift`:

```swift
import XCTest
import CairnCore
@testable import CairnStorage

final class SessionDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var workspaceId: UUID!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(name: "W", cwd: "/tmp")
        try await WorkspaceDAO.upsert(ws, in: db)
        workspaceId = ws.id
    }

    func test_upsert_insertsNewSession() async throws {
        let s = Session(workspaceId: workspaceId, jsonlPath: "/s.jsonl",
                        startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await SessionDAO.upsert(s, in: db)
        let fetched = try await SessionDAO.fetch(id: s.id, in: db)
        XCTAssertEqual(fetched, s)
    }

    func test_updateCursor_bumpsByteOffsetAndLine() async throws {
        let s = Session(workspaceId: workspaceId, jsonlPath: "/s.jsonl",
                        startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await SessionDAO.upsert(s, in: db)
        try await SessionDAO.updateCursor(
            sessionId: s.id,
            byteOffset: 12345,
            lastLineNumber: 67,
            in: db
        )
        let fetched = try await SessionDAO.fetch(id: s.id, in: db)
        XCTAssertEqual(fetched?.byteOffset, 12345)
        XCTAssertEqual(fetched?.lastLineNumber, 67)
        XCTAssertEqual(fetched?.state, .live, "updateCursor 不应改 state")
    }

    func test_fetchByWorkspace_returnsSessionsForGivenWorkspace() async throws {
        let otherWs = Workspace(name: "Other", cwd: "/other")
        try await WorkspaceDAO.upsert(otherWs, in: db)

        let s1 = Session(workspaceId: workspaceId, jsonlPath: "/1.jsonl",
                         startedAt: Date(timeIntervalSince1970: 1))
        let s2 = Session(workspaceId: workspaceId, jsonlPath: "/2.jsonl",
                         startedAt: Date(timeIntervalSince1970: 2))
        let s3 = Session(workspaceId: otherWs.id, jsonlPath: "/3.jsonl",
                         startedAt: Date(timeIntervalSince1970: 3))
        for s in [s1, s2, s3] { try await SessionDAO.upsert(s, in: db) }

        let inMain = try await SessionDAO.fetchAll(workspaceId: workspaceId, in: db)
        XCTAssertEqual(Set(inMain.map(\.id)), Set([s1.id, s2.id]))
    }

    func test_fetchByState_live_idle() async throws {
        let live = Session(workspaceId: workspaceId, jsonlPath: "/live",
                           startedAt: Date(), state: .live)
        let idle = Session(workspaceId: workspaceId, jsonlPath: "/idle",
                           startedAt: Date(), state: .idle)
        let ended = Session(workspaceId: workspaceId, jsonlPath: "/ended",
                            startedAt: Date(), state: .ended)
        for s in [live, idle, ended] { try await SessionDAO.upsert(s, in: db) }

        let active = try await SessionDAO.fetchActive(in: db)
        XCTAssertEqual(Set(active.map(\.id)), Set([live.id, idle.id]),
                       "fetchActive 应命中 spec §D 的 idx_sessions_state 索引(state IN ('live','idle'))")
    }

    func test_delete_cascadesFromWorkspace() async throws {
        let s = Session(workspaceId: workspaceId, jsonlPath: "/s.jsonl",
                        startedAt: Date())
        try await SessionDAO.upsert(s, in: db)
        // 删除 workspace → session 应 CASCADE 删除
        try await WorkspaceDAO.delete(id: workspaceId, in: db)
        let fetched = try await SessionDAO.fetch(id: s.id, in: db)
        XCTAssertNil(fetched, "spec §D workspace_id FK ON DELETE CASCADE")
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter SessionDAOTests 2>&1 | tail -5
```

- [ ] **Step 3:写 SessionDAO**

`Sources/CairnStorage/DAOs/SessionDAO.swift`:

```swift
import Foundation
import GRDB
import CairnCore

public enum SessionDAO {
    public static func upsert(_ s: Session, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO sessions
                    (id, workspace_id, jsonl_path, byte_offset, last_line_number,
                     started_at, ended_at, state, model_used, is_imported)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    s.id.uuidString,
                    s.workspaceId.uuidString,
                    s.jsonlPath,
                    s.byteOffset,
                    s.lastLineNumber,
                    ISO8601.string(from: s.startedAt),
                    s.endedAt.map(ISO8601.string(from:)),
                    s.state.rawValue,
                    s.modelUsed,
                    s.isImported ? 1 : 0,
                ]
            )
        }
    }

    /// 增量更新 cursor,其他字段不变。JSONLWatcher 每次 ingest 块后调用。
    public static func updateCursor(
        sessionId: UUID,
        byteOffset: Int64,
        lastLineNumber: Int64,
        in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE sessions
                    SET byte_offset = ?, last_line_number = ?
                    WHERE id = ?
                """,
                arguments: [byteOffset, lastLineNumber, sessionId.uuidString]
            )
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> Session? {
        try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM sessions WHERE id = ?",
                arguments: [id.uuidString]
            ).map { try Self.make(from: $0) }
        }
    }

    public static func fetchAll(workspaceId: UUID, in db: CairnDatabase) async throws -> [Session] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM sessions WHERE workspace_id = ? ORDER BY started_at DESC",
                arguments: [workspaceId.uuidString]
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    /// 活跃 session(state IN ('live','idle')),对应 spec §D idx_sessions_state。
    public static func fetchActive(in db: CairnDatabase) async throws -> [Session] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM sessions WHERE state IN ('live', 'idle')"
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    public static func delete(id: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM sessions WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Row mapping

    private static func make(from row: Row) throws -> Session {
        Session(
            id: try row.uuid("id"),
            workspaceId: try row.uuid("workspace_id"),
            jsonlPath: row\["jsonl_path"],
            startedAt: try row.date("started_at"),
            endedAt: try row.dateIfPresent("ended_at"),
            byteOffset: row\["byte_offset"],
            lastLineNumber: row\["last_line_number"],
            modelUsed: row["model_used"],
            isImported: (row["is_imported"] as Int? ?? 0) == 1,
            state: try row.rawEnum("state", as: SessionState.self)
        )
    }
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter SessionDAOTests 2>&1 | tail -5
```

**Expected**:`Executed 5 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnStorage/DAOs/SessionDAO.swift Tests/CairnStorageTests/SessionDAOTests.swift
git commit -m "feat(storage): SessionDAO + updateCursor 增量 + 5 CRUD 测试

fetchActive 方法匹配 spec §D idx_sessions_state 索引(state IN ('live','idle'))。
updateCursor 单独方法供 JSONLWatcher 高频调用,避免整行 upsert。
CASCADE 测试验证 workspace 删除时 session 自动清理。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T7:TaskDAO + task_sessions 关联表 + CRUD 测试

**Files:**
- Create: `Sources/CairnStorage/DAOs/TaskDAO.swift`
- Create: `Tests/CairnStorageTests/TaskDAOTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnStorageTests/TaskDAOTests.swift`:

```swift
import XCTest
import CairnCore
@testable import CairnStorage

final class TaskDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var workspaceId: UUID!
    private var sessionId1: UUID!
    private var sessionId2: UUID!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(name: "W", cwd: "/w")
        try await WorkspaceDAO.upsert(ws, in: db)
        workspaceId = ws.id

        let s1 = Session(workspaceId: ws.id, jsonlPath: "/1", startedAt: Date())
        let s2 = Session(workspaceId: ws.id, jsonlPath: "/2", startedAt: Date())
        try await SessionDAO.upsert(s1, in: db)
        try await SessionDAO.upsert(s2, in: db)
        sessionId1 = s1.id
        sessionId2 = s2.id
    }

    func test_upsert_singleSession_1to1() async throws {
        let task = CairnTask(workspaceId: workspaceId, title: "T",
                             sessionIds: [sessionId1])
        try await TaskDAO.upsert(task, in: db)
        let fetched = try await TaskDAO.fetch(id: task.id, in: db)
        XCTAssertEqual(fetched, task)
    }

    func test_upsert_multiSession_replacesJoinRows() async throws {
        let id = UUID()
        let now = Date()
        let v1 = CairnTask(id: id, workspaceId: workspaceId, title: "T",
                           sessionIds: [sessionId1],
                           createdAt: now, updatedAt: now)
        try await TaskDAO.upsert(v1, in: db)

        let v2 = CairnTask(id: id, workspaceId: workspaceId, title: "T",
                           sessionIds: [sessionId1, sessionId2],
                           createdAt: now, updatedAt: now)
        try await TaskDAO.upsert(v2, in: db)

        let fetched = try await TaskDAO.fetch(id: id, in: db)
        XCTAssertEqual(Set(fetched?.sessionIds ?? []), Set([sessionId1, sessionId2]))
    }

    func test_upsert_emptySessionIds_ok() async throws {
        let task = CairnTask(workspaceId: workspaceId, title: "Empty",
                             sessionIds: [])
        try await TaskDAO.upsert(task, in: db)
        let fetched = try await TaskDAO.fetch(id: task.id, in: db)
        XCTAssertEqual(fetched?.sessionIds, [])
    }

    func test_fetchByWorkspace_andStatus() async throws {
        let active = CairnTask(workspaceId: workspaceId, title: "A",
                               status: .active, sessionIds: [])
        let done = CairnTask(workspaceId: workspaceId, title: "B",
                             status: .completed, sessionIds: [])
        try await TaskDAO.upsert(active, in: db)
        try await TaskDAO.upsert(done, in: db)

        let activeOnly = try await TaskDAO.fetchAll(
            workspaceId: workspaceId, status: .active, in: db)
        XCTAssertEqual(activeOnly.map(\.id), [active.id])
    }

    func test_delete_cascadesTaskSessions() async throws {
        let task = CairnTask(workspaceId: workspaceId, title: "T",
                             sessionIds: [sessionId1, sessionId2])
        try await TaskDAO.upsert(task, in: db)
        try await TaskDAO.delete(id: task.id, in: db)

        // 确认 task_sessions 行已清理
        let joinCount = try await db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task_sessions WHERE task_id = ?",
                arguments: [task.id.uuidString]
            ) ?? -1
        }
        XCTAssertEqual(joinCount, 0)
    }

    func test_codable_and_row_roundTrip_fullTask() async throws {
        let task = CairnTask(
            id: UUID(),
            workspaceId: workspaceId,
            title: "完整字段",
            intent: "所有字段都有值",
            status: .completed,
            sessionIds: [sessionId1, sessionId2],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_003_600),
            completedAt: Date(timeIntervalSince1970: 1_700_003_600)
        )
        try await TaskDAO.upsert(task, in: db)
        let fetched = try await TaskDAO.fetch(id: task.id, in: db)
        XCTAssertEqual(fetched, task)
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter TaskDAOTests 2>&1 | tail -5
```

- [ ] **Step 3:写 TaskDAO**

`Sources/CairnStorage/DAOs/TaskDAO.swift`:

```swift
import Foundation
import GRDB
import CairnCore

public enum TaskDAO {
    /// Upsert tasks 行 + 同步 task_sessions 关联(delete-then-insert 模式)。
    public static func upsert(_ task: CairnTask, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO tasks
                    (id, workspace_id, title, intent, status,
                     created_at, updated_at, completed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    task.id.uuidString,
                    task.workspaceId.uuidString,
                    task.title,
                    task.intent,
                    task.status.rawValue,
                    ISO8601.string(from: task.createdAt),
                    ISO8601.string(from: task.updatedAt),
                    task.completedAt.map(ISO8601.string(from:)),
                ]
            )
            // 清理旧关联
            try db.execute(
                sql: "DELETE FROM task_sessions WHERE task_id = ?",
                arguments: [task.id.uuidString]
            )
            // 按当前 sessionIds 重建
            let now = ISO8601.string(from: Date())
            for sid in task.sessionIds {
                try db.execute(
                    sql: """
                        INSERT INTO task_sessions (task_id, session_id, attached_at)
                        VALUES (?, ?, ?)
                    """,
                    arguments: [task.id.uuidString, sid.uuidString, now]
                )
            }
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> CairnTask? {
        try await db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM tasks WHERE id = ?",
                arguments: [id.uuidString]
            ) else { return nil }

            let sessionIds = try UUID.fetchAll(
                db,
                sql: "SELECT session_id FROM task_sessions WHERE task_id = ?",
                arguments: [id.uuidString]
            )

            return try CairnTask(
                id: try row.uuid("id"),
                workspaceId: try row.uuid("workspace_id"),
                title: row\["title"],
                intent: row["intent"],
                status: try row.rawEnum("status", as: TaskStatus.self),
                sessionIds: sessionIds,
                createdAt: try row.date("created_at"),
                updatedAt: try row.date("updated_at"),
                completedAt: try row.dateIfPresent("completed_at")
            )
        }
    }

    public static func fetchAll(
        workspaceId: UUID,
        status: TaskStatus? = nil,
        in db: CairnDatabase
    ) async throws -> [CairnTask] {
        try await db.read { db in
            var sql = "SELECT id FROM tasks WHERE workspace_id = ?"
            var args: [DatabaseValueConvertible] = [workspaceId.uuidString]
            if let status {
                sql += " AND status = ?"
                args.append(status.rawValue)
            }
            sql += " ORDER BY updated_at DESC"
            let ids = try UUID.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return try ids.compactMap { id -> CairnTask? in
                try Self.fetchSync(id: id, db: db)
            }
        }
    }

    public static func delete(id: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            // task_sessions 通过 ON DELETE CASCADE 自动删除,这里只删 tasks 行
            try db.execute(
                sql: "DELETE FROM tasks WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - 同步 helper(复用,避免 fetchAll 里重复 await)

    private static func fetchSync(id: UUID, db: GRDB.Database) throws -> CairnTask? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM tasks WHERE id = ?",
            arguments: [id.uuidString]
        ) else { return nil }

        let sessionIds = try UUID.fetchAll(
            db,
            sql: "SELECT session_id FROM task_sessions WHERE task_id = ?",
            arguments: [id.uuidString]
        )

        return try CairnTask(
            id: try row.uuid("id"),
            workspaceId: try row.uuid("workspace_id"),
            title: row\["title"],
            intent: row["intent"],
            status: try row.rawEnum("status", as: TaskStatus.self),
            sessionIds: sessionIds,
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            completedAt: try row.dateIfPresent("completed_at")
        )
    }
}
```

**注**:`UUID.fetchAll(db, sql:...)` 依赖 UUID 符合 `DatabaseValueConvertible`。**GRDB 7 不内置此 conformance**,本 plan T4 在 `Row+Mapping.swift` 里显式补了 `extension UUID: DatabaseValueConvertible`(用 `.uuidString` 作为 TEXT 存取),所以这里的 `UUID.fetchAll(...)` 可用。

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter TaskDAOTests 2>&1 | tail -5
```

**Expected**:`Executed 6 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnStorage/DAOs/TaskDAO.swift Tests/CairnStorageTests/TaskDAOTests.swift
git commit -m "feat(storage): TaskDAO + task_sessions join 同步 + 6 CRUD 测试

upsert 走 delete-then-insert 同步 task_sessions 关联(避免复杂 diff);
fetchAll 支持 workspaceId + 可选 status 过滤(spec §6.2 sidebar);
CASCADE 测试确认删 task 时 task_sessions 行自动清理。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T8:EventDAO + 分页 + 配对查询 + CRUD 测试

**Files:**
- Create: `Sources/CairnStorage/DAOs/EventDAO.swift`
- Create: `Tests/CairnStorageTests/EventDAOTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnStorageTests/EventDAOTests.swift`:

```swift
import XCTest
import CairnCore
@testable import CairnStorage

final class EventDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var sessionId: UUID!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(name: "W", cwd: "/w")
        try await WorkspaceDAO.upsert(ws, in: db)
        let s = Session(workspaceId: ws.id, jsonlPath: "/s", startedAt: Date())
        try await SessionDAO.upsert(s, in: db)
        sessionId = s.id
    }

    func test_upsert_andFetch_fullFields() async throws {
        let event = Event(
            id: UUID(),
            sessionId: sessionId,
            type: .toolUse,
            category: .shell,
            toolName: "Bash",
            toolUseId: "toolu_01",
            pairedEventId: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            lineNumber: 42,
            blockIndex: 0,
            summary: "ls -la",
            rawPayloadJson: #"{"type":"tool_use"}"#,
            byteOffsetInJsonl: 12345
        )
        try await EventDAO.upsert(event, in: db)
        let fetched = try await EventDAO.fetch(id: event.id, in: db)
        XCTAssertEqual(fetched, event)
    }

    func test_upsertBatch_allInOneTransaction() async throws {
        let events = (1...100).map { i in
            Event(sessionId: sessionId, type: .assistantText,
                  timestamp: Date(timeIntervalSince1970: Double(i)),
                  lineNumber: Int64(i), summary: "msg \(i)")
        }
        try await EventDAO.upsertBatch(events, in: db)
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0
        }
        XCTAssertEqual(count, 100)
    }

    func test_fetchBySession_pagination() async throws {
        let events = (1...50).map { i in
            Event(sessionId: sessionId, type: .assistantText,
                  timestamp: Date(timeIntervalSince1970: Double(i)),
                  lineNumber: Int64(i), summary: "msg \(i)")
        }
        try await EventDAO.upsertBatch(events, in: db)

        let page1 = try await EventDAO.fetch(
            sessionId: sessionId, limit: 20, offset: 0, in: db)
        let page2 = try await EventDAO.fetch(
            sessionId: sessionId, limit: 20, offset: 20, in: db)

        XCTAssertEqual(page1.count, 20)
        XCTAssertEqual(page2.count, 20)
        XCTAssertEqual(page1.first?.lineNumber, 1,
                       "应按 (line_number, block_index) 升序")
        XCTAssertEqual(page1.last?.lineNumber, 20)
        XCTAssertEqual(page2.first?.lineNumber, 21)
    }

    func test_fetchByToolUseId_forPairing() async throws {
        let use = Event(sessionId: sessionId, type: .toolUse,
                        toolName: "Read", toolUseId: "t1",
                        timestamp: Date(), lineNumber: 1, summary: "read")
        let result = Event(sessionId: sessionId, type: .toolResult,
                           toolUseId: "t1",
                           timestamp: Date(), lineNumber: 2, summary: "result")
        try await EventDAO.upsert(use, in: db)
        try await EventDAO.upsert(result, in: db)

        let matches = try await EventDAO.fetchByToolUseId("t1", in: db)
        XCTAssertEqual(Set(matches.map(\.id)), Set([use.id, result.id]))
    }

    func test_fetchByType() async throws {
        let err = Event(sessionId: sessionId, type: .error,
                        timestamp: Date(), lineNumber: 1, summary: "err")
        let txt = Event(sessionId: sessionId, type: .assistantText,
                        timestamp: Date(), lineNumber: 2, summary: "ok")
        try await EventDAO.upsert(err, in: db)
        try await EventDAO.upsert(txt, in: db)

        let errors = try await EventDAO.fetchByType(
            .error, sessionId: sessionId, in: db)
        XCTAssertEqual(errors.map(\.id), [err.id])
    }

    func test_delete_cascadesFromSession() async throws {
        let event = Event(sessionId: sessionId, type: .userMessage,
                          timestamp: Date(), lineNumber: 1, summary: "hi")
        try await EventDAO.upsert(event, in: db)
        try await SessionDAO.delete(id: sessionId, in: db)

        let fetched = try await EventDAO.fetch(id: event.id, in: db)
        XCTAssertNil(fetched, "session CASCADE 应带走 events")
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter EventDAOTests 2>&1 | tail -5
```

- [ ] **Step 3:写 EventDAO**

`Sources/CairnStorage/DAOs/EventDAO.swift`:

```swift
import Foundation
import GRDB
import CairnCore

public enum EventDAO {
    public static func upsert(_ event: Event, in db: CairnDatabase) async throws {
        try await db.write { db in
            try Self.upsertSync(event, db: db)
        }
    }

    /// 批量 upsert,单事务。JSONL ingest 每 chunk 调用。
    /// spec §7.8:单事务 ≤ 500 条,调用方按需切分。
    public static func upsertBatch(
        _ events: [Event],
        in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            for e in events {
                try Self.upsertSync(e, db: db)
            }
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> Event? {
        try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM events WHERE id = ?",
                arguments: [id.uuidString]
            ).map { try Self.make(from: $0) }
        }
    }

    /// 按 session 分页取 event,排序 (line_number ASC, block_index ASC)。
    public static func fetch(
        sessionId: UUID, limit: Int, offset: Int,
        in db: CairnDatabase
    ) async throws -> [Event] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM events
                    WHERE session_id = ?
                    ORDER BY line_number ASC, block_index ASC
                    LIMIT ? OFFSET ?
                """,
                arguments: [sessionId.uuidString, limit, offset]
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    /// 按 toolUseId 查(spec §4.4 配对用)。
    public static func fetchByToolUseId(
        _ toolUseId: String, in db: CairnDatabase
    ) async throws -> [Event] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM events
                    WHERE tool_use_id = ?
                    ORDER BY line_number ASC, block_index ASC
                """,
                arguments: [toolUseId]
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    public static func fetchByType(
        _ type: EventType, sessionId: UUID,
        in db: CairnDatabase
    ) async throws -> [Event] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM events
                    WHERE session_id = ? AND type = ?
                    ORDER BY line_number ASC, block_index ASC
                """,
                arguments: [sessionId.uuidString, type.rawValue]
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    public static func delete(id: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM events WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - helpers

    private static func upsertSync(_ e: Event, db: GRDB.Database) throws {
        try db.execute(
            sql: """
                INSERT OR REPLACE INTO events
                (id, session_id, type, category, tool_name, tool_use_id,
                 paired_event_id, timestamp, line_number, block_index,
                 summary, raw_payload_json, byte_offset_in_jsonl)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        )
    }

    private static func make(from row: Row) throws -> Event {
        Event(
            id: try row.uuid("id"),
            sessionId: try row.uuid("session_id"),
            type: try row.rawEnum("type", as: EventType.self),
            category: (row["category"] as String?).map { ToolCategory(rawValue: $0) },
            toolName: row["tool_name"],
            toolUseId: row["tool_use_id"],
            pairedEventId: try row.uuidIfPresent("paired_event_id"),
            timestamp: try row.date("timestamp"),
            lineNumber: row\["line_number"],
            blockIndex: row\["block_index"],
            summary: row\["summary"],
            rawPayloadJson: row["raw_payload_json"],
            byteOffsetInJsonl: row["byte_offset_in_jsonl"]
        )
    }
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter EventDAOTests 2>&1 | tail -5
```

**Expected**:`Executed 6 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnStorage/DAOs/EventDAO.swift Tests/CairnStorageTests/EventDAOTests.swift
git commit -m "feat(storage): EventDAO + upsertBatch + 分页 + 配对查询 + 6 测试

upsertBatch 单事务入库 N 条(spec §7.8 每批 ≤ 500 调用方切分)。
fetch(sessionId:limit:offset:) 分页按 (line_number, block_index) 升序,
对应 spec §D idx_events_session_seq 索引。
fetchByToolUseId 供 spec §4.4 tool_use ↔ tool_result 配对用。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T9:BudgetDAO + CRUD 测试

**Files:**
- Create: `Sources/CairnStorage/DAOs/BudgetDAO.swift`
- Create: `Tests/CairnStorageTests/BudgetDAOTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnStorageTests/BudgetDAOTests.swift`:

```swift
import XCTest
import CairnCore
@testable import CairnStorage

final class BudgetDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var taskId: UUID!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(name: "W", cwd: "/w")
        try await WorkspaceDAO.upsert(ws, in: db)
        let task = CairnTask(workspaceId: ws.id, title: "T", sessionIds: [])
        try await TaskDAO.upsert(task, in: db)
        taskId = task.id
    }

    func test_upsert_withAllCaps() async throws {
        let b = Budget(
            taskId: taskId,
            maxInputTokens: 100_000,
            maxOutputTokens: 50_000,
            maxCostUSD: 5.0,
            maxWallSeconds: 3600,
            usedInputTokens: 1000,
            usedOutputTokens: 500,
            usedCostUSD: 0.25,
            usedWallSeconds: 60,
            state: .normal,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await BudgetDAO.upsert(b, in: db)
        let fetched = try await BudgetDAO.fetch(taskId: taskId, in: db)
        XCTAssertEqual(fetched, b)
    }

    func test_upsert_withAllNilCaps() async throws {
        let b = Budget(taskId: taskId, updatedAt: Date(timeIntervalSince1970: 1))
        try await BudgetDAO.upsert(b, in: db)
        let fetched = try await BudgetDAO.fetch(taskId: taskId, in: db)
        XCTAssertEqual(fetched, b)
    }

    func test_fetch_returnsNilForMissing() async throws {
        let fetched = try await BudgetDAO.fetch(taskId: UUID(), in: db)
        XCTAssertNil(fetched)
    }

    func test_state_rawValueRoundtrip() async throws {
        for state in BudgetState.allCases {
            let taskNew = CairnTask(workspaceId: try await WorkspaceDAO.fetchAll(in: db).first!.id,
                                    title: "t-\(state.rawValue)", sessionIds: [])
            try await TaskDAO.upsert(taskNew, in: db)
            let b = Budget(taskId: taskNew.id, state: state,
                           updatedAt: Date(timeIntervalSince1970: 1))
            try await BudgetDAO.upsert(b, in: db)
            let fetched = try await BudgetDAO.fetch(taskId: taskNew.id, in: db)
            XCTAssertEqual(fetched?.state, state)
        }
    }

    func test_delete_cascadesFromTask() async throws {
        let b = Budget(taskId: taskId, maxCostUSD: 5.0,
                       updatedAt: Date(timeIntervalSince1970: 1))
        try await BudgetDAO.upsert(b, in: db)
        try await TaskDAO.delete(id: taskId, in: db)
        let fetched = try await BudgetDAO.fetch(taskId: taskId, in: db)
        XCTAssertNil(fetched)
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter BudgetDAOTests 2>&1 | tail -5
```

- [ ] **Step 3:写 BudgetDAO**

`Sources/CairnStorage/DAOs/BudgetDAO.swift`:

```swift
import Foundation
import GRDB
import CairnCore

public enum BudgetDAO {
    public static func upsert(_ b: Budget, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO budgets
                    (task_id,
                     max_input_tokens, max_output_tokens, max_cost_usd, max_wall_seconds,
                     used_input_tokens, used_output_tokens, used_cost_usd, used_wall_seconds,
                     state, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    b.taskId.uuidString,
                    b.maxInputTokens,
                    b.maxOutputTokens,
                    b.maxCostUSD,
                    b.maxWallSeconds,
                    b.usedInputTokens,
                    b.usedOutputTokens,
                    b.usedCostUSD,
                    b.usedWallSeconds,
                    b.state.rawValue,
                    ISO8601.string(from: b.updatedAt),
                ]
            )
        }
    }

    public static func fetch(taskId: UUID, in db: CairnDatabase) async throws -> Budget? {
        try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM budgets WHERE task_id = ?",
                arguments: [taskId.uuidString]
            ).map { try Self.make(from: $0) }
        }
    }

    public static func delete(taskId: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM budgets WHERE task_id = ?",
                arguments: [taskId.uuidString]
            )
        }
    }

    private static func make(from row: Row) throws -> Budget {
        Budget(
            taskId: try row.uuid("task_id"),
            maxInputTokens: row["max_input_tokens"],
            maxOutputTokens: row["max_output_tokens"],
            maxCostUSD: row["max_cost_usd"],
            maxWallSeconds: row["max_wall_seconds"],
            usedInputTokens: row\["used_input_tokens"],
            usedOutputTokens: row\["used_output_tokens"],
            usedCostUSD: row\["used_cost_usd"],
            usedWallSeconds: row\["used_wall_seconds"],
            state: try row.rawEnum("state", as: BudgetState.self),
            updatedAt: try row.date("updated_at")
        )
    }
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter BudgetDAOTests 2>&1 | tail -5
```

**Expected**:`Executed 5 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnStorage/DAOs/BudgetDAO.swift Tests/CairnStorageTests/BudgetDAOTests.swift
git commit -m "feat(storage): BudgetDAO + state 枚举 rawValue roundtrip + 5 测试

task_id 作为主键,一 task 一 budget(1:1);
INSERT OR REPLACE 语义既能插入也能更新(spec §D 定义的约束)。
state 全 4 种枚举 rawValue 都验证 roundtrip;CASCADE 行为覆盖。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T10:PlanDAO + steps_json 序列化 + CRUD 测试

**Files:**
- Create: `Sources/CairnStorage/DAOs/PlanDAO.swift`
- Create: `Tests/CairnStorageTests/PlanDAOTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnStorageTests/PlanDAOTests.swift`:

```swift
import XCTest
import CairnCore
@testable import CairnStorage

final class PlanDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var taskId: UUID!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(name: "W", cwd: "/w")
        try await WorkspaceDAO.upsert(ws, in: db)
        let task = CairnTask(workspaceId: ws.id, title: "T", sessionIds: [])
        try await TaskDAO.upsert(task, in: db)
        taskId = task.id
    }

    func test_upsert_withEmptySteps() async throws {
        let plan = Plan(taskId: taskId, source: .manual, steps: [],
                        updatedAt: Date(timeIntervalSince1970: 1))
        try await PlanDAO.upsert(plan, in: db)
        let fetched = try await PlanDAO.fetch(id: plan.id, in: db)
        XCTAssertEqual(fetched, plan)
    }

    func test_upsert_withMultiStepsAllFields() async throws {
        let plan = Plan(
            id: UUID(),
            taskId: taskId,
            source: .todoWrite,
            steps: [
                PlanStep(content: "S1", status: .completed, priority: .high),
                PlanStep(content: "S2", status: .inProgress, priority: .medium),
                PlanStep(content: "S3", status: .pending, priority: .low),
            ],
            markdownRaw: "# My Plan\n- [x] S1\n",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await PlanDAO.upsert(plan, in: db)
        let fetched = try await PlanDAO.fetch(id: plan.id, in: db)
        XCTAssertEqual(fetched, plan)
    }

    func test_fetchByTask_latestFirst() async throws {
        let old = Plan(taskId: taskId, source: .planMd,
                       updatedAt: Date(timeIntervalSince1970: 1))
        let newer = Plan(taskId: taskId, source: .manual,
                         updatedAt: Date(timeIntervalSince1970: 2))
        try await PlanDAO.upsert(old, in: db)
        try await PlanDAO.upsert(newer, in: db)
        let plans = try await PlanDAO.fetchByTask(taskId: taskId, in: db)
        XCTAssertEqual(plans.map(\.id), [newer.id, old.id])
    }

    func test_delete() async throws {
        let plan = Plan(taskId: taskId, source: .manual,
                        updatedAt: Date(timeIntervalSince1970: 1))
        try await PlanDAO.upsert(plan, in: db)
        try await PlanDAO.delete(id: plan.id, in: db)
        let fetched = try await PlanDAO.fetch(id: plan.id, in: db)
        XCTAssertNil(fetched)
    }

    func test_cascadeFromTask() async throws {
        let plan = Plan(taskId: taskId, source: .manual,
                        updatedAt: Date(timeIntervalSince1970: 1))
        try await PlanDAO.upsert(plan, in: db)
        try await TaskDAO.delete(id: taskId, in: db)
        let fetched = try await PlanDAO.fetch(id: plan.id, in: db)
        XCTAssertNil(fetched)
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter PlanDAOTests 2>&1 | tail -5
```

- [ ] **Step 3:写 PlanDAO**

`Sources/CairnStorage/DAOs/PlanDAO.swift`:

```swift
import Foundation
import GRDB
import CairnCore

public enum PlanDAO {
    public static func upsert(_ plan: Plan, in db: CairnDatabase) async throws {
        let stepsJson = String(
            data: try CairnCore.jsonEncoder.encode(plan.steps),
            encoding: .utf8
        ) ?? "[]"
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO plans
                    (id, task_id, source, steps_json, markdown_raw, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    plan.id.uuidString,
                    plan.taskId.uuidString,
                    plan.source.rawValue,
                    stepsJson,
                    plan.markdownRaw,
                    ISO8601.string(from: plan.updatedAt),
                ]
            )
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> Plan? {
        try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM plans WHERE id = ?",
                arguments: [id.uuidString]
            ).map { try Self.make(from: $0) }
        }
    }

    /// 按 task 查,按 updated_at DESC(spec §D idx_plans_task 索引)。
    public static func fetchByTask(taskId: UUID, in db: CairnDatabase) async throws -> [Plan] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM plans WHERE task_id = ? ORDER BY updated_at DESC",
                arguments: [taskId.uuidString]
            )
            return try rows.map { try Self.make(from: $0) }
        }
    }

    public static func delete(id: UUID, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM plans WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    private static func make(from row: Row) throws -> Plan {
        let stepsJson: String = row\["steps_json"]
        let steps: [PlanStep] = try CairnCore.jsonDecoder.decode(
            [PlanStep].self,
            from: Data(stepsJson.utf8)
        )
        return Plan(
            id: try row.uuid("id"),
            taskId: try row.uuid("task_id"),
            source: try row.rawEnum("source", as: PlanSource.self),
            steps: steps,
            markdownRaw: row["markdown_raw"],
            updatedAt: try row.date("updated_at")
        )
    }
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter PlanDAOTests 2>&1 | tail -5
```

**Expected**:`Executed 5 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnStorage/DAOs/PlanDAO.swift Tests/CairnStorageTests/PlanDAOTests.swift
git commit -m "feat(storage): PlanDAO + steps_json 序列化 + 5 测试

steps 数组用 CairnCore.jsonEncoder(ISO-8601)序列化到 TEXT 列;
反序列化用 CairnCore.jsonDecoder,roundtrip 保真。
fetchByTask 按 updated_at DESC(spec §D idx_plans_task)。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T11:LayoutStateDAO + ApprovalDAO + SettingsDAO + 测试

**Files:**
- Create: `Sources/CairnStorage/DAOs/LayoutStateDAO.swift`
- Create: `Sources/CairnStorage/DAOs/ApprovalDAO.swift`
- Create: `Sources/CairnStorage/DAOs/SettingsDAO.swift`
- Create: `Tests/CairnStorageTests/LayoutStateDAOTests.swift`
- Create: `Tests/CairnStorageTests/ApprovalDAOTests.swift`
- Create: `Tests/CairnStorageTests/SettingsDAOTests.swift`

这是**批量 task**,一次把 3 个相似 DAO 做完。每个 DAO + 测试共 ~50 行。

- [ ] **Step 1:写 LayoutStateDAO 测试**

`Tests/CairnStorageTests/LayoutStateDAOTests.swift`:

```swift
import XCTest
import CairnCore
@testable import CairnStorage

final class LayoutStateDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var workspaceId: UUID!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(name: "W", cwd: "/w")
        try await WorkspaceDAO.upsert(ws, in: db)
        workspaceId = ws.id
    }

    func test_upsert_andFetch() async throws {
        let payload = #"{"tabs":[{"id":"t1","active":true}]}"#
        try await LayoutStateDAO.upsert(
            workspaceId: workspaceId,
            layoutJson: payload,
            updatedAt: Date(timeIntervalSince1970: 1),
            in: db
        )
        let (json, updatedAt) = try await LayoutStateDAO.fetch(
            workspaceId: workspaceId, in: db)!
        XCTAssertEqual(json, payload)
        XCTAssertEqual(updatedAt, Date(timeIntervalSince1970: 1))
    }

    func test_fetchMissing_returnsNil() async throws {
        let result = try await LayoutStateDAO.fetch(
            workspaceId: UUID(), in: db)
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2:写 LayoutStateDAO**

`Sources/CairnStorage/DAOs/LayoutStateDAO.swift`:

```swift
import Foundation
import GRDB

/// 窗口/标签布局。存储为 JSON blob(layout schema 由 CairnUI 定义,M1.3 起用)。
public enum LayoutStateDAO {
    public static func upsert(
        workspaceId: UUID,
        layoutJson: String,
        updatedAt: Date,
        in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO layout_states
                    (workspace_id, layout_json, updated_at)
                    VALUES (?, ?, ?)
                """,
                arguments: [
                    workspaceId.uuidString,
                    layoutJson,
                    ISO8601.string(from: updatedAt),
                ]
            )
        }
    }

    public static func fetch(
        workspaceId: UUID, in db: CairnDatabase
    ) async throws -> (layoutJson: String, updatedAt: Date)? {
        try await db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM layout_states WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            ) else { return nil }
            let json: String = row\["layout_json"]
            let updated: Date = try row.date("updated_at")
            return (json, updated)
        }
    }
}
```

- [ ] **Step 3:写 ApprovalDAO 测试 + 实现(v1.1 skeleton,M1.2 只确保能 CRUD)**

`Tests/CairnStorageTests/ApprovalDAOTests.swift`:

```swift
import XCTest
import CairnCore
@testable import CairnStorage

final class ApprovalDAOTests: XCTestCase {
    private var db: CairnDatabase!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
    }

    func test_upsert_andFetch_minimalFields() async throws {
        let id = UUID()
        try await ApprovalDAO.upsert(
            id: id,
            sessionId: nil,
            toolName: "Bash",
            toolInputJson: #"{"command":"ls"}"#,
            decision: "approved",
            decidedBy: "user",
            decidedAt: Date(timeIntervalSince1970: 1_700_000_000),
            reason: "routine",
            in: db
        )
        let record = try await ApprovalDAO.fetch(id: id, in: db)
        XCTAssertEqual(record?.toolName, "Bash")
        XCTAssertEqual(record?.decision, "approved")
    }
}
```

`Sources/CairnStorage/DAOs/ApprovalDAO.swift`:

```swift
import Foundation
import GRDB

/// Hook 审批决策(v1.1 起用)。M1.2 提供 CRUD 骨架,
/// v1.1 HookManager 实装时再构造领域类型封装。
public enum ApprovalDAO {
    /// 对应 spec §D approvals 表的完整字段。
    public struct Record: Equatable, Sendable {
        public let id: UUID
        public let sessionId: UUID?
        public let toolName: String
        public let toolInputJson: String
        public let decision: String
        public let decidedBy: String
        public let decidedAt: Date
        public let reason: String?
    }

    public static func upsert(
        id: UUID,
        sessionId: UUID?,
        toolName: String,
        toolInputJson: String,
        decision: String,
        decidedBy: String,
        decidedAt: Date,
        reason: String?,
        in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO approvals
                    (id, session_id, tool_name, tool_input_json,
                     decision, decided_by, decided_at, reason)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id.uuidString,
                    sessionId?.uuidString,
                    toolName,
                    toolInputJson,
                    decision,
                    decidedBy,
                    ISO8601.string(from: decidedAt),
                    reason,
                ]
            )
        }
    }

    public static func fetch(id: UUID, in db: CairnDatabase) async throws -> Record? {
        try await db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM approvals WHERE id = ?",
                arguments: [id.uuidString]
            ) else { return nil }
            return Record(
                id: try row.uuid("id"),
                sessionId: try row.uuidIfPresent("session_id"),
                toolName: row\["tool_name"],
                toolInputJson: row\["tool_input_json"],
                decision: row\["decision"],
                decidedBy: row\["decided_by"],
                decidedAt: try row.date("decided_at"),
                reason: row["reason"]
            )
        }
    }
}
```

- [ ] **Step 4:写 SettingsDAO 测试 + 实现**

`Tests/CairnStorageTests/SettingsDAOTests.swift`:

```swift
import XCTest
import CairnCore
@testable import CairnStorage

final class SettingsDAOTests: XCTestCase {
    private var db: CairnDatabase!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
    }

    func test_setAndGet() async throws {
        try await SettingsDAO.set(
            key: "terminal.font", valueJson: #""SF Mono""#, in: db)
        let val = try await SettingsDAO.get(key: "terminal.font", in: db)
        XCTAssertEqual(val, #""SF Mono""#)
    }

    func test_getMissing_returnsNil() async throws {
        XCTAssertNil(try await SettingsDAO.get(key: "nope", in: db))
    }

    func test_setOverrides() async throws {
        try await SettingsDAO.set(key: "k", valueJson: "1", in: db)
        try await SettingsDAO.set(key: "k", valueJson: "2", in: db)
        XCTAssertEqual(try await SettingsDAO.get(key: "k", in: db), "2")
    }
}
```

`Sources/CairnStorage/DAOs/SettingsDAO.swift`:

```swift
import Foundation
import GRDB

/// 键值对配置存储。value 存 JSON 字符串,调用方自行 decode。
public enum SettingsDAO {
    public static func set(
        key: String, valueJson: String, in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO settings (key, value_json, updated_at)
                    VALUES (?, ?, ?)
                """,
                arguments: [key, valueJson, ISO8601.string(from: Date())]
            )
        }
    }

    public static func get(
        key: String, in db: CairnDatabase
    ) async throws -> String? {
        try await db.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value_json FROM settings WHERE key = ?",
                arguments: [key]
            )
        }
    }

    public static func delete(key: String, in db: CairnDatabase) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM settings WHERE key = ?",
                arguments: [key]
            )
        }
    }
}
```

- [ ] **Step 5:跑三组测试确认绿**

```bash
swift test --filter LayoutStateDAOTests 2>&1 | tail -3
swift test --filter ApprovalDAOTests 2>&1 | tail -3
swift test --filter SettingsDAOTests 2>&1 | tail -3
```

**Expected**:全 0 failure。累计 2 + 1 + 3 = 6 tests。

- [ ] **Step 6:Commit**

```bash
git add Sources/CairnStorage/DAOs/{LayoutStateDAO,ApprovalDAO,SettingsDAO}.swift \
        Tests/CairnStorageTests/{LayoutStateDAOTests,ApprovalDAOTests,SettingsDAOTests}.swift
git commit -m "feat(storage): LayoutState + Approval(v1.1 骨架)+ Settings DAO + 6 测试

LayoutStateDAO 为 M1.3 布局持久化准备;存 JSON blob,workspace_id 主键。
ApprovalDAO 是 v1.1 hook 审批 skeleton,M1.2 只确保 CRUD 可用,
v1.1 时再构造领域 Approval 类型封装。
SettingsDAO 键值对存储,value 为 JSON 字符串,调用方自行 decode。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T12:swift build + swift test 全绿 验证

**Files:** 无新增。

- [ ] **Step 1:完整 swift build**

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift build 2>&1 | tail -3
```

**Expected**:`Build complete!`,本项目代码无 error/warning。

- [ ] **Step 2:完整 swift test**

```bash
swift test 2>&1 | tail -10
```

**Expected**:`Executed N tests, with 0 failures`,N ≥ 100(M1.1 的 54 + M1.2 新增 ~45-50 = ≥ 99)。

累加预估:
- CairnStorageTests smoke: 2
- MigrationTests: 4
- WorkspaceDAOTests: 6
- SessionDAOTests: 5
- TaskDAOTests: 6
- EventDAOTests: 6
- BudgetDAOTests: 5
- PlanDAOTests: 5
- LayoutStateDAOTests: 2
- ApprovalDAOTests: 1
- SettingsDAOTests: 3

M1.2 合计:45 个新测试
M1.1 保留:54 个
总计:**≥ 99 tests**。

- [ ] **Step 3:确认 CairnApp 仍可启动(回归)**

```bash
./scripts/make-app-bundle.sh debug --open 2>&1 | tail -3
sleep 3
pgrep -fl "Cairn.app/Contents/MacOS/CairnApp" | head -1
pkill -f "Cairn.app/Contents/MacOS/CairnApp" 2>/dev/null
```

**Expected**:脚本打印 "启动中",`pgrep` 打印活跃 PID。

**失败排查**:若 M1.2 意外破坏 M0.2 的 CairnApp(理论上不会,因为 CairnStorage 不被 CairnApp 直接依赖),检查 Package.swift 的 `.executableTarget(name: "CairnApp", dependencies: [...])`。

- [ ] **Step 4:不 commit**(本 task 只是验证 gate)

---

## T13:milestone-log + tag m1-2-done + push

**Files:**
- Modify: `docs/milestone-log.md`

- [ ] **Step 1:更新 milestone-log.md**

用 Edit 工具在 `docs/milestone-log.md`:

(a) 把 `- [ ] M1.2 CairnStorage(GRDB + 11 表 + migrator)` 从"待完成"删除。

(b) 在 "已完成(逆序)" 下、**M1.1 条目之前**插入:

```markdown
### M1.2 CairnStorage(GRDB + 11 表 + migrator + DAO)

**Completed**: 2026-04-24(或 Claude 实际完成日)
**Tag**: `m1-2-done`
**Commits**: ~12 个(T1-T11)

**Summary**:
- Package.swift 加 GRDB 7.10.0 依赖(tools-version 5.9 不变,SwiftPM 跨版本依赖无障碍)
- CairnStorage 模块完整落地:`CairnDatabase` actor(封装 DatabaseQueue)+ `DatabaseConfiguration`(PRAGMA)+ `DatabaseMigrator`(v1 schema)+ 9 个 DAO + Row 映射辅助
- 11 张表全部创建,索引齐全(spec §D),`schema_versions(1, ...)` 已插入
- ≥ 45 个 CRUD 单测全绿;CASCADE / UNIQUE / 分页 / 枚举 rawValue roundtrip 全覆盖
- CairnCore 与 CairnStorage 严格单向依赖;DAO 不暴露 GRDB 原生类型给 CairnServices 上层

**关键设计决策**(plan pinned):
- `DatabaseQueue` 不是 `DatabasePool`(桌面单进程,写少读多但读无并发瓶颈)
- Date 存 ISO-8601 TEXT(不是 GRDB 默认 double)—— spec §7.2 硬要求
- DAO 手写 `from(row:)` / `toArguments()`,不用 GRDB `FetchableRecord` 自动合成 —— 列名 snake_case 与 Swift camelCase 映射精确可控
- `Plan.steps` 用 `steps_json` 列存 JSON(spec §D)
- `CairnTask.sessionIds` 走 `task_sessions` 关联表(spec §D),DAO upsert 用 delete-then-insert 模式同步

**Acceptance**: 见 M1.2 计划文档 T15 验收清单。

**Known limitations**:
- Approval DAO 是 v1.1 skeleton(CRUD 可用),领域类型封装留 v1.1 HookManager
- `synchronous=NORMAL` PRAGMA 未启用,M4.3 性能测试时按需加
- 备份 / 归档 / 诊断导出(spec §7.6)留 M4.3
- raw_payload_json 90 天归档策略(spec §7.4)留 M4.3
```

- [ ] **Step 2:Commit**

```bash
git add docs/milestone-log.md
git commit -m "docs(log): M1.2 完成记录

12 commits / 99+ tests green / 11 张表 + 9 DAO + migrator。
CairnCore 的内存领域模型现已完整持久化到 SQLite。
M1.3 起可基于 LayoutState 持久化 UI 状态。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 3:Push + Tag**

```bash
git push origin main 2>&1 | tail -3
git tag -a m1-2-done -m "M1.2 完成:CairnStorage(GRDB + 11 表 + migrator + DAO)"
git push origin m1-2-done 2>&1 | tail -3
```

- [ ] **Step 4:最终验证**

```bash
git status
git log --oneline -15
git tag -l
```

---

## T14:(本 plan 不需要独立 task,归并到 T2 里已完成占位清理)

**跳过**。删除 M1.1 留的 `Sources/CairnStorage/Storage.swift` 已在 T2 Step 6 完成。

---

## T15:验收清单(用户执行)

**Owner**: 用户。

Claude 完成 T1-T13 后,在 session 末尾输出以下验收清单:

```markdown
## M1.2 验收清单

**交付物**:
- `Package.swift` 加 GRDB 7.10.0 依赖(tools-version 5.9 **不变**)
- `Sources/CairnStorage/` 14 个新 Swift 文件(CairnStorage / Database / DatabaseConfiguration / Schema/{Migrations,SchemaV1} / DAOs/{9个} / Support/{Row+Mapping})
- `Tests/CairnStorageTests/` 11 个新测试文件
- ≥ 45 个新 CRUD 单测全绿;M1.1 的 54 个保持绿
- git tag `m1-2-done` 本地 + 远端

**前置条件**:网络可访问 github.com/groue/GRDB.swift(首次拉依赖 60-120s)。

**验证步骤**:

步骤 1 · 编译通过
```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift build 2>&1 | tail -3
```
期望:`Build complete!`,本项目无 error/warning(GRDB 自身 warning 忽略)。

步骤 2 · 全测试集绿
```bash
swift test 2>&1 | tail -5
```
期望:`Executed 99+ tests, with 0 failures`(M1.1 的 54 + M1.2 的 ~45)。

步骤 3 · 新增文件就位
```bash
ls Sources/CairnStorage/
ls Sources/CairnStorage/DAOs/
ls Sources/CairnStorage/Schema/
ls Sources/CairnStorage/Support/
ls Tests/CairnStorageTests/
```
期望:
- `Sources/CairnStorage/` 含 CairnStorage.swift / Database.swift / DatabaseConfiguration.swift + DAOs / Schema / Support 子目录
- `DAOs/` 有 9 个 .swift
- `Schema/` 有 Migrations.swift + SchemaV1.swift
- `Support/` 有 Row+Mapping.swift
- `Tests/CairnStorageTests/` 有 11 个测试 .swift

步骤 4 · Git 状态 + tag + 远端
```bash
git status
git log --oneline -20
git tag -l
git ls-remote origin refs/tags/m1-2-done 2>&1 | head -1
```
期望:`working tree clean`,tag `m1-2-done` 在本地 + 远端。

步骤 5 · CairnApp 仍可启动(M0.2 回归)
```bash
./scripts/make-app-bundle.sh debug --open
# 确认终端窗口正常弹出,⌘Q 关闭
```
期望:M1.2 引入 CairnStorage 不影响 CairnApp UI 层(CairnApp 暂未依赖 CairnStorage)。

**已知限制 / 延后项**:
- Approval DAO 是 v1.1 skeleton(功能 OK,缺领域封装)
- 性能 PRAGMA / 备份 / 归档 / 诊断导出留 M4.3
- raw_payload_json 90 天归档留 M4.3
- CairnServices / CairnUI 还未使用 CairnStorage(M1.3 起)

**下个 M**:**M1.3 SwiftUI 主窗口三区 + Sidebar/Panel 可折叠**(spec §6 布局)。
```

---

## 回归 Self-Review

### 1. Spec 覆盖

| Spec 位置 | 要求 | 对应 Task | 状态 |
|---|---|---|---|
| §2.5 状态归属 | Cairn 拥有 Budget/Task/Event/Layout/Approval | T5-T11 | ✅ |
| §3.2 依赖方向 | CairnStorage 只 import CairnCore + GRDB | Package.swift T1 | ✅ |
| §3.4 并发模型 | CairnStorage DAO 内置 serial writer | T2 Database actor | ✅ |
| §7.1 存储位置 | `~/Library/Application Support/Cairn/cairn.sqlite` | T2 DatabaseLocation | ✅ |
| §7.2 Schema | 11 张表 + 索引 | T3 Migrations + SchemaV1 | ✅ |
| §7.3 Migration | `DatabaseMigrator` + 备份前migration | T3(备份留 M4.3) | ✅ 主体 |
| §7.8 PRAGMA | `cache_size=-64000;foreign_keys=ON` | T2 DatabaseConfiguration | ✅(synchronous=NORMAL 延后 M4.3)|
| §D 11 表 SQL | 全部 CREATE TABLE + 索引 | T3 SchemaV1.statements | ✅ + 补 is_imported |
| §8.4 M1.2 要求 | `schema_versions` 插入 v1;完整 CRUD 单测;单测全绿 | T3 + T5-T11 + T12 | ✅ |

**1 个有意延后**:备份/归档/诊断导出(§7.3 / §7.4 / §7.6)明示留 M4.3,不算 M1.2 gap。

### 2. Placeholder 扫描

- "TBD" / "TODO" / "FIXME" / "implement later" / "appropriate error" — 本 plan 无违规
- "(或 Claude 实际完成日)"、"(T1-T11)" 等出现在 T13 模板中,是**执行时填入**,不是 plan 漏项
- 所有 Swift / SQL 代码块完整可粘贴
- 所有 `git commit` message 完整含 Co-Authored-By

### 3. 类型 / 命名一致性

- `CairnDatabase` actor 名,各 DAO 用 `in db: CairnDatabase` 参数签名 —— 跨 T2-T11 一致
- `CairnStorage.makeMigrator()` 入口,在 T2 smoke / T3 测试 / 各 DAO setUp 反复使用 —— 一致
- `WorkspaceDAO.upsert(_ ws: Workspace, in: db)` 签名模式 —— 所有 DAO 按此规律(first-arg 实体,named `in:` db)
- `fetch(id:in:)` vs `fetchAll(...)` vs `fetchByTask(...)` 命名有差异但语义清晰:
  - `fetch(id:)` 单个 primary key 查
  - `fetchAll(...)` 无过滤全返
  - `fetchBy*(...)` 按某维度过滤
- `Session.isImported` 映射到 `is_imported INTEGER NOT NULL DEFAULT 0` —— T3 SchemaV1 和 T6 SessionDAO 一致
- `Plan.steps` 用 `steps_json TEXT NOT NULL` 列,T10 PlanDAO 用 `CairnCore.jsonEncoder` —— 跨 M1.1 + M1.2 链路一致

### 4. 任务归属明确

- T1-T13 Claude 全做,T14 归并到 T2,T15 用户执行
- 无模糊区域

### 5. 潜在风险

**风险 1(低)**:**swift-tools-version 5.9 依赖 GRDB(tools 6.1)的实际可行性**。
SwiftPM 规则允许低 tools-version 包依赖高 tools-version 包(各 manifest 独立解析),本机 Swift 6.3.1 能处理两边。但如果 SwiftPM 真的报 "package requires tools-version 6.1",T1 Step 2 失败排查已给出升级到 6.1 的具体步骤(含加 `.swiftLanguageMode(.v5)` 避免 Swift 6 严格模式)。

**风险 2(已消除)**:**UUID 的 DatabaseValueConvertible conformance**。
初稿假设 GRDB 7 内置此 conformance,自检发现**不内置**。T4 Row+Mapping.swift 现已显式加上 `extension UUID: DatabaseValueConvertible`(`.uuidString` ↔ TEXT 列),所有 `UUID.fetchAll/fetchOne(...)` 调用都走此扩展,无运行时惊喜。

**风险 3(低)**:**`Row.subscript<T>(column)` 对 NOT NULL 列的行为**。
对 NOT NULL 列,subscript 返回 `T?`,nil 表示列不存在或值是 NULL。我们在 DAO make 函数里 `row\["title"]` 等调用,若列缺失会返回 nil 并在强解包位置 crash。
用 T4 的 `decode` helper 更严格,但 plan 为简洁未用。若测试意外 crash,替换为 `try row.decode("title")` 即可(我们要增加此 helper,或直接用 GRDB 内置)。

**风险 4(低)**:**Swift 5 模式能否调用 GRDB 7 的 Swift 6 API**。
GRDB 7 导出的 `Sendable` 类型在 Swift 5 模式下仍可 import(ABI 层面 Sendable 是协议 stamp,不挑调用方语言模式)。
若遇到 API 签名 Swift 5 不认,说明 GRDB 7 用了 Swift 6 专用语法(`each` 泛型参数包等),需要升我们的 tools-version 到 6.0 并在 CairnStorage target 加 `.swiftLanguageMode(.v6)`。但 GRDB 是主流库,不会用新奇语法阻塞 Swift 5 调用方。

### 6. 结论

Plan 完整可执行,设计决策 pinned,无 placeholder,命令可直接粘贴。
T1 tools-version 升级是**唯一需要外部验证**的点(swift package resolve 能不能跑),已有兜底方案。
其余 Task 都是标准 TDD 节奏:写测试 → 红 → 写实现 → 绿 → commit。
执行者按 T1-T13 走,T12 的 99+ tests 全绿即 milestone 达成。
