import XCTest
@testable import TweakKitMCP

final class TweakKitMCPServerTests: XCTestCase {
    private var server: TweakKitMCPServer!
    private let port = 18090

    override func setUpWithError() throws {
        server = TweakKitMCPServer()
        try server.start(port: port, token: "test-token")
    }

    override func tearDown() {
        server.stop(immediately: true)
    }

    private func post(_ body: String, headers: [String: String]) throws -> (status: Int, body: String) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let done = expectation(description: "response")
        var result: (Int, String) = (-1, "")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            result = ((response as? HTTPURLResponse)?.statusCode ?? -1, String(decoding: data ?? Data(), as: UTF8.self))
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        return result
    }

    private let ping = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#

    func testBearerTokenAuthorizes() throws {
        let response = try post(ping, headers: ["Authorization": "Bearer test-token"])
        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(response.body.contains("\"result\""), response.body)
    }

    func testMissingOrWrongTokenIsRejected() throws {
        XCTAssertEqual(try post(ping, headers: [:]).status, 401)
        XCTAssertEqual(try post(ping, headers: ["Authorization": "Bearer nope"]).status, 401)
    }

    func testNotificationReturnsAccepted() throws {
        let response = try post(
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            headers: ["Authorization": "Bearer test-token"]
        )
        XCTAssertEqual(response.status, 202)
    }

    func testForeignOriginIsForbidden() throws {
        let response = try post(ping, headers: ["Authorization": "Bearer test-token", "Origin": "https://evil.example"])
        XCTAssertEqual(response.status, 403)
    }

    func testClaudeCodeCommand() throws {
        XCTAssertEqual(
            server.claudeCodeCommand,
            "claude mcp add --transport http tweakkit http://127.0.0.1:\(port)/mcp --header \"Authorization: Bearer test-token\""
        )
    }
}
