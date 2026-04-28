import Foundation

/// JSONL 一行的通用表层 schema(user / assistant / system / 其他)。
/// content 是异构的(str / list of mixed blocks),用原始 JSON `[String: Any]`
/// 表示,由 JSONLParser 按需拆。
public struct JSONLEntry {
    public let type: String
    public let parentUuid: String?
    /// 区分 "JSON 里 `parentUuid: null`"(true) vs "无 parentUuid 字段"(false)。
    /// compact_boundary 只在**显式 null**时派生;metadata entry(permission-mode
    /// 等)根本没 parentUuid 字段,不应派生。
    public let parentUuidExplicitlyNull: Bool
    public let timestamp: Date?
    public let sessionId: String?
    public let uuid: String?
    public let cwd: String?
    public let message: [String: Any]?
    /// 是否是 subagent sidechain(claude code 的子会话)
    public let isSidechain: Bool?
    /// 原始 JSON 字符串,raw_payload 用
    public let rawJson: String

    public enum ParseError: Error {
        case invalidJSON
        case missingType
    }

    public static func parse(_ line: String) throws -> JSONLEntry {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        guard let type = obj["type"] as? String else {
            throw ParseError.missingType
        }
        let timestamp: Date? = {
            guard let s = obj["timestamp"] as? String else { return nil }
            // 真实 Claude JSONL timestamp 两种格式并存:
            //   "2024-01-02T03:04:05.123Z"(含毫秒)
            //   "2024-01-02T03:04:05Z"(不含)
            // 只配一个 formatter 会漏解其中一种,回落到另一种。
            if let d = ISO8601DateFormatter.withFractional.date(from: s) { return d }
            return ISO8601DateFormatter.basic.date(from: s)
        }()
        let parentUuidField: Any? = obj["parentUuid"]
        return JSONLEntry(
            type: type,
            parentUuid: parentUuidField as? String,
            parentUuidExplicitlyNull: parentUuidField is NSNull,
            timestamp: timestamp,
            sessionId: obj["sessionId"] as? String,
            uuid: obj["uuid"] as? String,
            cwd: obj["cwd"] as? String,
            message: obj["message"] as? [String: Any],
            isSidechain: obj["isSidechain"] as? Bool,
            rawJson: line
        )
    }
}

// 统一 ISO8601 解码器(两个,对应两种真实格式)
private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
