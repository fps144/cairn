import XCTest
@testable import CairnClaude

final class IncrementalReaderTests: XCTestCase {
    private func makeTempFile(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inc-\(UUID().uuidString).jsonl")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func test_readsCompleteLines() throws {
        let url = try makeTempFile(#"""
        {"a":1}
        {"b":2}
        {"c":3}

        """#)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 0, maxBytes: 1 << 20
        )
        XCTAssertEqual(result.lines, [#"{"a":1}"#, #"{"b":2}"#, #"{"c":3}"#])
        XCTAssertEqual(result.newOffset, 24)
        XCTAssertEqual(result.linesRead, 3)
    }

    func test_dropsIncompleteTrailingLine() throws {
        let url = try makeTempFile(#"""
        {"a":1}
        {"b":
        """#)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 0, maxBytes: 1 << 20
        )
        XCTAssertEqual(result.lines, [#"{"a":1}"#])
        XCTAssertEqual(result.newOffset, 8)
    }

    func test_resumesFromOffset() throws {
        let url = try makeTempFile(#"""
        {"a":1}
        {"b":2}
        {"c":3}

        """#)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 8, maxBytes: 1 << 20
        )
        XCTAssertEqual(result.lines, [#"{"b":2}"#, #"{"c":3}"#])
        XCTAssertEqual(result.newOffset, 24)
    }

    func test_returnsEmptyWhenAtEOF() throws {
        let url = try makeTempFile(#"""
        {"a":1}

        """#)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 8, maxBytes: 1 << 20
        )
        XCTAssertEqual(result.lines, [])
        XCTAssertEqual(result.newOffset, 8)
        XCTAssertEqual(result.linesRead, 0)
    }

    func test_handlesEmptyLines() throws {
        let url = try makeTempFile("{\"a\":1}\n\n{\"b\":2}\n")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 0, maxBytes: 1 << 20
        )
        XCTAssertEqual(result.lines, [#"{"a":1}"#, "", #"{"b":2}"#])
        XCTAssertEqual(result.newOffset, 17)
    }

    func test_respectsMaxBytes() throws {
        let lines = (0..<10).map { #"{"n":\#($0)}"# }
        let url = try makeTempFile(lines.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try IncrementalReader.read(
            fileURL: url, fromOffset: 0, maxBytes: 20
        )
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.newOffset, 16)
    }
}
