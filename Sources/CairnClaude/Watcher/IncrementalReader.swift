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
