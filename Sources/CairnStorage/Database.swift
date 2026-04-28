import Foundation
import GRDB

/// Cairn 数据库入口。底层走 GRDB `DatabaseQueue`(线程安全,内部序列化)。
///
/// 历史上这里是 `actor`,但 `DatabaseQueue` 本身就保证串行化,actor 包装
/// 把所有调用变成 async suspension —— 对"app 退出前必须落盘"的路径是个坑:
/// `Task { await db.write(...) }` 在 Cmd+Q 时被进程终止来不及 resume,最后
/// 一次 layout save 静默丢失。改成 `final class` 后同步 API 就能暴露给主线程
/// 退出路径。异步 API 保留,现有 DAO 调用点全部不变。
public final class CairnDatabase: @unchecked Sendable {
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
        try migrator.migrate(queue)
    }

    /// 只读闭包(async 签名,保留向后兼容)。
    public func read<T: Sendable>(
        _ body: @Sendable (GRDB.Database) throws -> T
    ) async throws -> T {
        try await queue.read(body)
    }

    /// 写入闭包(async 签名,保留向后兼容)。含隐式事务;闭包抛错则回滚。
    public func write<T: Sendable>(
        _ body: @Sendable (GRDB.Database) throws -> T
    ) async throws -> T {
        try await queue.write(body)
    }

    /// 同步只读。用于 app 终止路径等必须立即返回的场景。
    public func readSync<T>(
        _ body: (GRDB.Database) throws -> T
    ) throws -> T {
        try queue.read(body)
    }

    /// 同步写入。用于 app 终止路径等必须立即落盘的场景。
    public func writeSync<T>(
        _ body: (GRDB.Database) throws -> T
    ) throws -> T {
        try queue.write(body)
    }
}
