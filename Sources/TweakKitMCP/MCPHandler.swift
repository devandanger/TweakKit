import Foundation
import TweakKitCore

/// Transport-independent MCP (Model Context Protocol) request handler.
///
/// Takes raw JSON-RPC 2.0 message bytes and returns the response bytes, or `nil`
/// when the input contained only notifications/responses (which get no reply).
final class MCPHandler {
    static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]
    static let serverName = "TweakKit"
    static let serverVersion = "0.1.0"

    enum ErrorCode {
        static let parseError = -32700
        static let invalidRequest = -32600
        static let methodNotFound = -32601
        static let invalidParams = -32602
    }

    private let tools: MCPTools

    init(registry: TweakRegistry) {
        self.tools = MCPTools(registry: registry)
    }

    func handle(data: Data) -> Data? {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return encode(errorResponse(id: NSNull(), code: ErrorCode.parseError, message: "Parse error"))
        }

        if let batch = json as? [Any] {
            guard !batch.isEmpty else {
                return encode(errorResponse(id: NSNull(), code: ErrorCode.invalidRequest, message: "Empty batch"))
            }
            let responses = batch.compactMap { handle(message: $0) }
            return responses.isEmpty ? nil : encode(responses)
        }

        return handle(message: json).flatMap(encode)
    }

    // MARK: - Messages

    private func handle(message: Any) -> [String: Any]? {
        guard let object = message as? [String: Any],
              object["jsonrpc"] as? String == "2.0" else {
            return errorResponse(id: NSNull(), code: ErrorCode.invalidRequest, message: "Invalid Request")
        }

        guard let method = object["method"] as? String else {
            // A response from the client (we never send requests), so nothing to reply.
            return nil
        }

        guard let id = object["id"], !(id is NSNull) else {
            // Notification (e.g. notifications/initialized, notifications/cancelled): no reply.
            return nil
        }

        let params = object["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return success(id: id, result: initializeResult(params: params))
        case "ping":
            return success(id: id, result: [:])
        case "tools/list":
            return success(id: id, result: ["tools": MCPTools.definitions])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return errorResponse(id: id, code: ErrorCode.invalidParams, message: "Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard let result = tools.call(name: name, arguments: arguments) else {
                return errorResponse(id: id, code: ErrorCode.invalidParams, message: "Unknown tool: \(name)")
            }
            return success(id: id, result: result)
        default:
            return errorResponse(id: id, code: ErrorCode.methodNotFound, message: "Method not found: \(method)")
        }
    }

    private func initializeResult(params: [String: Any]) -> [String: Any] {
        let requested = params["protocolVersion"] as? String
        let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
            ?? Self.supportedProtocolVersions[0]
        return [
            "protocolVersion": version,
            "capabilities": [
                "tools": ["listChanged": false]
            ],
            "serverInfo": [
                "name": Self.serverName,
                "version": Self.serverVersion
            ],
            "instructions": """
            TweakKit exposes runtime-tweakable values in a running app. Use list_tweaks to \
            discover keys, types, current values and constraints, then set_tweak to change a \
            value live. Changes are in-memory overrides and take effect immediately; use \
            reset_tweak or reset_all_tweaks to restore defaults.
            """
        ]
    }

    // MARK: - Encoding

    private func success(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func encode(_ value: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
