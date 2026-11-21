import XCTest
import TweakKitCore
@testable import TweakKitMCP

final class MCPHandlerTests: XCTestCase {
    private let handler = MCPHandler(registry: .shared)

    private func send(_ message: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: message)
        let response = try XCTUnwrap(handler.handle(data: data))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
    }

    private func callTool(_ name: String, _ arguments: [String: Any] = [:]) throws -> (text: String, isError: Bool) {
        let response = try send([
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": name, "arguments": arguments]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        return (try XCTUnwrap(content.first?["text"] as? String), result["isError"] as? Bool ?? false)
    }

    func testInitializeNegotiatesProtocolVersion() throws {
        let response = try send([
            "jsonrpc": "2.0", "id": "init-1", "method": "initialize",
            "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]]
        ])
        XCTAssertEqual(response["id"] as? String, "init-1")
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
    }

    func testInitializeFallsBackToLatestForUnknownVersion() throws {
        let response = try send([
            "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "1999-01-01"]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, MCPHandler.supportedProtocolVersions[0])
    }

    func testNotificationGetsNoResponse() throws {
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(handler.handle(data: data))
    }

    func testParseErrorAndUnknownMethod() throws {
        let parse = try XCTUnwrap(handler.handle(data: Data("{not json".utf8)))
        let parseObject = try XCTUnwrap(JSONSerialization.jsonObject(with: parse) as? [String: Any])
        XCTAssertEqual((parseObject["error"] as? [String: Any])?["code"] as? Int, -32700)

        let unknown = try send(["jsonrpc": "2.0", "id": 2, "method": "resources/list"])
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testToolsListIncludesAllTools() throws {
        let response = try send(["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        let tools = try XCTUnwrap((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertEqual(names, ["list_tweaks", "get_tweak", "set_tweak", "reset_tweak", "reset_all_tweaks", "get_tweak_history"])
    }

    func testSetGetResetRoundTrip() throws {
        let key = "mcp.test.\(UUID().uuidString)"
        let tweak = Tweak<Double>(key, defaultValue: 1.0, constraints: TweakConstraints(min: 0, max: 10))

        let set = try callTool("set_tweak", ["key": key, "value": 4.5])
        XCTAssertFalse(set.isError, set.text)
        XCTAssertEqual(tweak.currentValue, 4.5)
        XCTAssertEqual(TweakRegistry.shared.lastTweak?.source, .mcp)

        let get = try callTool("get_tweak", ["key": key])
        XCTAssertTrue(get.text.contains("\"current\" : \"4.5\""), get.text)

        let invalid = try callTool("set_tweak", ["key": key, "value": "not a number"])
        XCTAssertTrue(invalid.isError)
        XCTAssertEqual(tweak.currentValue, 4.5)

        let reset = try callTool("reset_tweak", ["key": key])
        XCTAssertFalse(reset.isError, reset.text)
        XCTAssertEqual(tweak.currentValue, 1.0)
    }

    func testSetBoolFromJSONBoolean() throws {
        let key = "mcp.test.bool.\(UUID().uuidString)"
        let tweak = Tweak<Bool>(key, defaultValue: false)
        let result = try callTool("set_tweak", ["key": key, "value": true])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(tweak.currentValue)
    }

    func testUnknownKeyIsToolError() throws {
        let result = try callTool("get_tweak", ["key": "does.not.exist"])
        XCTAssertTrue(result.isError)
    }

    func testUnknownToolIsProtocolError() throws {
        let response = try send([
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "nope"]
        ])
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? Int, -32602)
    }
}
