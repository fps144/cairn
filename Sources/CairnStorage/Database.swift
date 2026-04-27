import Foundation
import GRDB

/// Cairn 数据库入口。actor 隔离所有 DB 访问。
///
/// 公开 API 只有 `read(_:)` / `write(_:)` 两个闭包形式。
/// DAO 通过注入 `CairnDatabase` 实例,在闭包内拿 `GRDB.Database` 做 CRUD。
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
        try await queue.read(body)
    }

    /// 写入闭包(含隐式事务)。闭包抛错则回滚。
    public func write<T: Sendable>(
        _ body: @Sendable (GRDB.Database) throws -> T
    ) async throws -> T {
        try await queue.write(body)
    }
}
