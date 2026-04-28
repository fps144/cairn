import Foundation

/// ~/.claude/projects/{hash}/ 的 hash 规则。M0.1 probe 实测:`/` `_` `.` → `-`。
/// 正向可算;逆向歧义(因为 `-` 不能判断原字符)。
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
