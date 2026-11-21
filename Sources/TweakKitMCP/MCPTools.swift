import Foundation
import TweakKitCore

/// The MCP tools TweakKit exposes, and their implementations against a `TweakRegistry`.
struct MCPTools {
    let registry: TweakRegistry

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let definitions: [[String: Any]] = [
        [
            "name": "list_tweaks",
            "description": "List the app's registered tweaks with their type, default value, current value and constraints (min/max/step).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "filter": [
                        "type": "string",
                        "description": "Optional case-insensitive substring to match against tweak keys."
                    ]
                ]
            ],
            "annotations": ["readOnlyHint": true]
        ],
        [
            "name": "get_tweak",
            "description": "Get a single tweak's type, default value, current value and constraints.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "key": ["type": "string", "description": "The tweak key, e.g. ui.cornerRadius."]
                ],
                "required": ["key"]
            ],
            "annotations": ["readOnlyHint": true]
        ],
        [
            "name": "set_tweak",
            "description": "Set a tweak's value in the running app. The value is parsed according to the tweak's type (String, Int, Double, Bool) and validated against its constraints. Takes effect immediately.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "key": ["type": "string", "description": "The tweak key."],
                    "value": [
                        "type": ["string", "number", "boolean"],
                        "description": "The new value. Bools accept true/false/yes/no/on/off/1/0."
                    ]
                ],
                "required": ["key", "value"]
            ],
            "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true]
        ],
        [
            "name": "reset_tweak",
            "description": "Reset a tweak to its default value.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "key": ["type": "string", "description": "The tweak key."]
                ],
                "required": ["key"]
            ],
            "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true]
        ],
        [
            "name": "reset_all_tweaks",
            "description": "Reset every tweak to its default value.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
            "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": true]
        ],
        [
            "name": "get_tweak_history",
            "description": "Get recent tweak change events (newest last), including who changed them (web, ui, code, mcp).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": [
                        "type": "integer",
                        "minimum": 1,
                        "description": "Maximum number of events to return (default 20)."
                    ]
                ]
            ],
            "annotations": ["readOnlyHint": true]
        ]
    ]

    /// Runs a tool. Returns `nil` if the tool name is unknown.
    func call(name: String, arguments: [String: Any]) -> [String: Any]? {
        switch name {
        case "list_tweaks":
            let filter = arguments["filter"] as? String
            return json(registry.list(filter: filter).map(describe))
        case "get_tweak":
            return withTweak(arguments) { json(describe($0)) }
        case "set_tweak":
            return withTweak(arguments) { tweak in
                guard let value = Self.stringValue(arguments["value"]) else {
                    return error("Missing or invalid 'value'. Provide a string, number or boolean.")
                }
                let previous = tweak.currentValueString
                switch registry.set(tweak.key, valueString: value, source: .mcp) {
                case .success:
                    var result = describe(tweak)
                    result["previous"] = previous
                    return json(result)
                case .failure(let failure):
                    return error("Could not set \(tweak.key) to \(value): \(failure)")
                }
            }
        case "reset_tweak":
            return withTweak(arguments) { tweak in
                switch registry.reset(tweak.key, source: .mcp) {
                case .success:
                    return json(describe(tweak))
                case .failure(let failure):
                    return error("Could not reset \(tweak.key): \(failure)")
                }
            }
        case "reset_all_tweaks":
            let tweaks = registry.list()
            let failures = tweaks.compactMap { tweak -> String? in
                if case .failure(let failure) = registry.reset(tweak.key, source: .mcp) {
                    return "\(tweak.key): \(failure)"
                }
                return nil
            }
            if !failures.isEmpty {
                return error("Some tweaks could not be reset:\n" + failures.joined(separator: "\n"))
            }
            return json(["reset": tweaks.count])
        case "get_tweak_history":
            let limit = max(1, Self.intValue(arguments["limit"]) ?? 20)
            let events = registry.history.suffix(limit).map { event -> [String: Any] in
                [
                    "key": event.key,
                    "old": event.oldValueString,
                    "new": event.newValueString,
                    "source": event.source.rawValue,
                    "timestamp": Self.timestampFormatter.string(from: event.timestamp)
                ]
            }
            return json(Array(events))
        default:
            return nil
        }
    }

    // MARK: - Helpers

    private func withTweak(_ arguments: [String: Any], _ body: (AnyTweakable) -> [String: Any]) -> [String: Any] {
        guard let key = arguments["key"] as? String, !key.isEmpty else {
            return error("Missing 'key'.")
        }
        guard let tweak = registry.get(key) else {
            return error("Unknown tweak key: \(key). Use list_tweaks to see available keys.")
        }
        return body(tweak)
    }

    private func describe(_ tweak: AnyTweakable) -> [String: Any] {
        var entry: [String: Any] = [
            "key": tweak.key,
            "type": tweak.typeName,
            "default": tweak.defaultValueString,
            "current": tweak.currentValueString
        ]
        if let constraints = tweak.constraintsInfo {
            var info: [String: Any] = [:]
            info["min"] = constraints.min
            info["max"] = constraints.max
            info["step"] = constraints.step
            entry["constraints"] = info
        }
        return entry
    }

    private func json(_ value: Any) -> [String: Any] {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return text(String(decoding: data, as: UTF8.self), isError: false)
    }

    private func error(_ message: String) -> [String: Any] {
        text(message, isError: true)
    }

    private func text(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    /// Converts a JSON scalar to the string form `setFromString` expects.
    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            // JSON booleans arrive as NSNumber backed by CFBoolean.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        default:
            return nil
        }
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}
