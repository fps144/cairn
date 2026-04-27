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
