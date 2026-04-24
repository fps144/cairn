import Foundation

/// CairnCore 共享的 JSON 编解码器。统一使用 ISO-8601 日期字符串。
///
/// spec §7.2:时间列一律 ISO-8601 字符串。
/// 使用场景:JSONL ingest 写入 summary JSON、SQLite 列存、导出诊断包。
extension CairnCore {
    /// 共享 JSONEncoder 单例。
    /// 注:JSONEncoder 的 `encode()` 方法在官方文档中**未明确保证**并发安全;
    /// M1.1 仅在单线程测试中使用,并发场景(M2.3 EventIngestor)届时按需
    /// 改为 per-call 新实例或用 actor 封装。
    public static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
