import XCTest
@testable import TweakKitServer

final class CommandParserTests: XCTestCase {
    func testTokenizeSplitsWhitespace() {
        let tokens = CommandParser.tokenize("list ui.theme")
        XCTAssertEqual(tokens, ["list", "ui.theme"])
    }

    func testTokenizeHandlesQuotedStrings() {
        let tokens = CommandParser.tokenize("set greeting \"hello world\"")
        XCTAssertEqual(tokens, ["set", "greeting", "hello world"])
    }

    func testTokenizeHandlesEscapedQuotesInQuotes() {
        let tokens = CommandParser.tokenize("set title \"hello \\\"world\\\"\"")
        XCTAssertEqual(tokens, ["set", "title", "hello \"world\""])
    }
}
