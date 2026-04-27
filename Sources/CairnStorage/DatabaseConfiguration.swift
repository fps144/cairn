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
