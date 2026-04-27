import Foundation

/// 解析 shell 通过 OSC 7 escape sequence 上报的 cwd。
/// 规范:`\033]7;file://hostname/path\007`
/// SwiftTerm 把 `file://hostname/path` 这段传给 delegate。
/// 我们用 URL 解析取 path 部分(自动 percent-decode)。
public enum OSC7Parser {
    /// 解析 OSC 7 字符串,返回 path;失败返回 nil。
    /// 接受:
    /// - `file://hostname/Users/sorain` → `/Users/sorain`
    /// - `file:///Users/sorain` → `/Users/sorain`(hostname 可空)
    /// - `/Users/sorain`(裸路径,兜底)→ 原样
    public static func parse(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 裸路径直接返回
        if trimmed.hasPrefix("/") {
            return trimmed
        }

        // file:// scheme 用 URL 解析
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "file" else {
            return nil
        }
        let path = url.path
        return path.isEmpty ? nil : path
    }
}
