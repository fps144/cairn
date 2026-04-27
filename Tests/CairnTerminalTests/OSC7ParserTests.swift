import XCTest
@testable import CairnTerminal

final class OSC7ParserTests: XCTestCase {
    func test_fileUrlWithHostname() {
        XCTAssertEqual(OSC7Parser.parse("file://imac/Users/sorain"),
                       "/Users/sorain")
    }

    func test_fileUrlEmptyHostname() {
        XCTAssertEqual(OSC7Parser.parse("file:///Users/sorain"),
                       "/Users/sorain")
    }

    func test_barePath_fallback() {
        XCTAssertEqual(OSC7Parser.parse("/Users/sorain"), "/Users/sorain")
    }

    func test_percentEncoded_decoded() {
        // "file:///Users/sor%20ain" → "/Users/sor ain"
        XCTAssertEqual(OSC7Parser.parse("file:///Users/sor%20ain"),
                       "/Users/sor ain")
    }

    func test_invalidScheme_returnsNil() {
        XCTAssertNil(OSC7Parser.parse("http://example.com/"))
        XCTAssertNil(OSC7Parser.parse(""))
    }
}
