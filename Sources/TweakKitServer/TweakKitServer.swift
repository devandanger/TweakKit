import Foundation
import Telegraph
import TweakKitCore

public final class TweakKitServer: ServerWebSocketDelegate {
    public enum NetworkMode {
        case localhostOnly
        case lan
    }

    private struct Session {
        weak var socket: WebSocket?
        var isWatching: Bool
        var watchKey: TweakKey?
    }

    private static let eventFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let server: Server
    private let registry: TweakRegistry
    private var registryObserverId: UUID?
    private let queue = DispatchQueue(label: "TweakKit.Server.state")
    private var sessions: [ObjectIdentifier: Session] = [:]
    private var routesConfigured = false

    public init(registry: TweakRegistry = .shared) {
        self.server = Server()
        self.registry = registry
        self.server.webSocketDelegate = self
    }

    public var port: Int {
        server.port
    }

    public var isRunning: Bool {
        server.isRunning
    }

    public func start(port: Int = 8080, networkMode: NetworkMode = .localhostOnly) throws {
        if !routesConfigured {
            configureRoutes()
            routesConfigured = true
        }
        let interface: String? = networkMode == .localhostOnly ? "127.0.0.1" : nil
        try server.start(port: port, interface: interface)
        installRegistryObserverIfNeeded()
    }

    public func stop(immediately: Bool = false) {
        server.stop(immediately: immediately)
        removeRegistryObserverIfNeeded()
        queue.sync {
            sessions.removeAll()
        }
    }

    private func configureRoutes() {
        server.route(.GET, "/") { _ in
            var headers = HTTPHeaders.empty
            headers.contentType = "text/html; charset=utf-8"
            return HTTPResponse(.ok, headers: headers, content: TerminalHTML.content)
        }

        server.route(.GET, "/health") { _ in
            var headers = HTTPHeaders.empty
            headers.contentType = "text/plain; charset=utf-8"
            return HTTPResponse(.ok, headers: headers, content: "OK")
        }

        server.route(.GET, "/api/tweaks") { _ in
            let payload = self.registry.list().map { tweak -> [String: Any] in
                var entry: [String: Any] = [
                    "key": tweak.key,
                    "type": tweak.typeName,
                    "default": tweak.defaultValueString,
                    "current": tweak.currentValueString
                ]
                if let constraints = tweak.constraintsInfo {
                    entry["constraints"] = [
                        "min": constraints.min as Any,
                        "max": constraints.max as Any,
                        "step": constraints.step as Any
                    ]
                }
                return entry
            }
            let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])) ?? Data()
            var headers = HTTPHeaders.empty
            headers.contentType = "application/json; charset=utf-8"
            return HTTPResponse(.ok, headers: headers, body: data)
        }
    }

    private func installRegistryObserverIfNeeded() {
        guard registryObserverId == nil else {
            return
        }
        registryObserverId = registry.addObserver { [weak self] event in
            self?.broadcast(event: event)
        }
    }

    private func removeRegistryObserverIfNeeded() {
        guard let id = registryObserverId else {
            return
        }
        registry.removeObserver(id)
        registryObserverId = nil
    }

    private func broadcast(event: TweakEvent) {
        let line = Self.format(event: event)
        queue.sync {
            let identifiers = sessions.keys
            for id in identifiers {
                guard var session = sessions[id] else {
                    continue
                }
                guard let socket = session.socket else {
                    sessions.removeValue(forKey: id)
                    continue
                }
                guard session.isWatching else {
                    continue
                }
                if let watchKey = session.watchKey, watchKey != event.key {
                    continue
                }
                socket.send(text: line)
                sessions[id] = session
            }
        }
    }

    private static func format(event: TweakEvent) -> String {
        let timestamp = event.timestamp
        let formatted = eventFormatter.string(from: timestamp)
        return "[\(formatted)] \(event.key): \(event.oldValueString) -> \(event.newValueString) (\(event.source.rawValue))"
    }

    public func server(_ server: Server, webSocketDidConnect webSocket: WebSocket, handshake: HTTPRequest) {
        let id = ObjectIdentifier(webSocket)
        queue.sync {
            sessions[id] = Session(socket: webSocket, isWatching: false, watchKey: nil)
        }
        send(lines: bannerLines(), to: webSocket)
    }

    public func server(_ server: Server, webSocketDidDisconnect webSocket: WebSocket, error: Error?) {
        let id = ObjectIdentifier(webSocket)
        queue.sync {
            sessions.removeValue(forKey: id)
        }
    }

    public func server(_ server: Server, webSocket: WebSocket, didReceiveMessage message: WebSocketMessage) {
        guard case .text(let text) = message.payload else {
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let responses = handle(commandLine: trimmed, from: webSocket)
        send(lines: responses, to: webSocket)
    }

    public func serverDidDisconnect(_ server: Server) {
        queue.sync {
            sessions.removeAll()
        }
    }

    private func bannerLines() -> [String] {
        return [
            "TweakKit Server",
            "Type 'help' for commands.",
            ""
        ]
    }

    private func handle(commandLine: String, from socket: WebSocket) -> [String] {
        let tokens = CommandParser.tokenize(commandLine)
        guard let command = tokens.first?.lowercased() else {
            return []
        }
        let args = Array(tokens.dropFirst())

        switch command {
        case "help":
            return helpLines()
        case "list":
            return listLines(filter: args.first)
        case "get":
            guard let key = args.first else {
                return ["usage: get <key>"]
            }
            return getLines(key: key)
        case "set":
            guard args.count >= 2 else {
                return ["usage: set <key> <value>"]
            }
            let key = args[0]
            let value = args[1]
            return setLines(key: key, value: value)
        case "reset":
            guard let key = args.first else {
                return ["usage: reset <key>"]
            }
            return resetLines(key: key)
        case "reset-all":
            return resetAllLines()
        case "last":
            return lastLines()
        case "history":
            let count = Int(args.first ?? "")
            return historyLines(limit: count)
        case "watch":
            return watchLines(args: args, socket: socket)
        default:
            return ["Unknown command: \(command)"]
        }
    }

    private func helpLines() -> [String] {
        return [
            "Commands:",
            "  help",
            "  list [filter]",
            "  get <key>",
            "  set <key> <value>",
            "  reset <key>",
            "  reset-all",
            "  last",
            "  history [n]",
            "  watch [key] | watch off"
        ]
    }

    private func listLines(filter: String?) -> [String] {
        let tweaks = registry.list(filter: filter)
        guard !tweaks.isEmpty else {
            return ["No tweaks found."]
        }
        return tweaks.map { describe($0) }
    }

    private func getLines(key: TweakKey) -> [String] {
        guard let tweak = registry.get(key) else {
            return ["No tweak with key: \(key)"]
        }
        return [describe(tweak)]
    }

    private func setLines(key: TweakKey, value: String) -> [String] {
        let result = registry.set(key, valueString: value, source: .web)
        switch result {
        case .success:
            return ["Set \(key) to \(value)"]
        case .failure(let error):
            return ["Error: \(error)"]
        }
    }

    private func resetLines(key: TweakKey) -> [String] {
        let result = registry.reset(key, source: .web)
        switch result {
        case .success:
            return ["Reset \(key)"]
        case .failure(let error):
            return ["Error: \(error)"]
        }
    }

    private func resetAllLines() -> [String] {
        let tweaks = registry.list()
        var count = 0
        for tweak in tweaks {
            let before = tweak.currentValueString
            if case .success = registry.reset(tweak.key, source: .web) {
                let after = tweak.currentValueString
                if before != after {
                    count += 1
                }
            }
        }
        return ["Reset \(count) tweaks"]
    }

    private func lastLines() -> [String] {
        guard let event = registry.lastTweak else {
            return ["No tweaks yet."]
        }
        return [Self.format(event: event)]
    }

    private func historyLines(limit: Int?) -> [String] {
        let limitValue = max(1, limit ?? 10)
        let events = registry.history.suffix(limitValue)
        guard !events.isEmpty else {
            return ["No history."]
        }
        return events.map { Self.format(event: $0) }
    }

    private func watchLines(args: [String], socket: WebSocket) -> [String] {
        let id = ObjectIdentifier(socket)
        if let first = args.first, first.lowercased() == "off" {
            queue.sync {
                if var session = sessions[id] {
                    session.isWatching = false
                    session.watchKey = nil
                    sessions[id] = session
                }
            }
            return ["Watch disabled"]
        }

        let watchKey = args.first
        queue.sync {
            if var session = sessions[id] {
                session.isWatching = true
                session.watchKey = watchKey
                sessions[id] = session
            }
        }
        if let watchKey {
            return ["Watching \(watchKey)"]
        }
        return ["Watching all tweaks"]
    }

    private func send(lines: [String], to socket: WebSocket) {
        guard !lines.isEmpty else {
            return
        }
        let payload = lines.joined(separator: "\n")
        socket.send(text: payload)
    }

    private func describe(_ tweak: AnyTweakable) -> String {
        var description = "\(tweak.key) = \(tweak.currentValueString) (default: \(tweak.defaultValueString)) [\(tweak.typeName)]"
        if let constraints = tweak.constraintsInfo {
            var pieces: [String] = []
            if let min = constraints.min {
                pieces.append("min=\(min)")
            }
            if let max = constraints.max {
                pieces.append("max=\(max)")
            }
            if let step = constraints.step {
                pieces.append("step=\(step)")
            }
            if !pieces.isEmpty {
                description += " {" + pieces.joined(separator: ", ") + "}"
            }
        }
        return description
    }
}

enum CommandParser {
    static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var isEscaping = false

        for char in line {
            if isEscaping {
                current.append(char)
                isEscaping = false
                continue
            }

            if char == "\\" && inQuotes {
                isEscaping = true
                continue
            }

            if char == "\"" {
                inQuotes.toggle()
                continue
            }

            if char.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(char)
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}

private enum TerminalHTML {
    static let content = """
    <!doctype html>
    <html>
      <head>
        <meta charset=\"utf-8\" />
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
        <title>TweakKit</title>
        <style>
          :root {
            --bg: #0b0c0f;
            --panel: #12141a;
            --text: #e7e9ee;
            --muted: #99a1b5;
            --accent: #7dd3fc;
          }
          * { box-sizing: border-box; }
          body {
            margin: 0;
            font-family: \"IBM Plex Mono\", \"Menlo\", \"Monaco\", monospace;
            background: radial-gradient(circle at top, #111827 0%, #0b0c0f 60%);
            color: var(--text);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            padding: 24px;
          }
          .terminal {
            width: min(960px, 100%);
            background: var(--panel);
            border: 1px solid #1f2330;
            border-radius: 12px;
            box-shadow: 0 24px 60px rgba(0,0,0,0.4);
            display: flex;
            flex-direction: column;
            overflow: hidden;
          }
          header {
            padding: 16px 20px;
            display: flex;
            align-items: center;
            gap: 12px;
            border-bottom: 1px solid #1f2330;
            background: linear-gradient(135deg, #0f172a, #12141a);
          }
          .dot { width: 10px; height: 10px; border-radius: 50%; background: #ef4444; box-shadow: 18px 0 0 #f59e0b, 36px 0 0 #22c55e; }
          header h1 {
            font-size: 14px;
            letter-spacing: 0.2em;
            text-transform: uppercase;
            margin: 0 0 0 12px;
            color: var(--muted);
          }
          #output {
            padding: 20px;
            min-height: 360px;
            max-height: 60vh;
            overflow-y: auto;
            white-space: pre-wrap;
            line-height: 1.6;
          }
          .line {
            margin-bottom: 8px;
            color: var(--text);
            opacity: 0;
            transform: translateY(6px);
            animation: reveal 0.2s ease forwards;
          }
          .prompt {
            display: flex;
            gap: 8px;
            padding: 14px 20px 20px;
            border-top: 1px solid #1f2330;
            background: #0e1118;
          }
          .prompt span {
            color: var(--accent);
          }
          input {
            flex: 1;
            background: transparent;
            border: none;
            color: var(--text);
            font-family: inherit;
            font-size: 14px;
            outline: none;
          }
          @keyframes reveal {
            to { opacity: 1; transform: translateY(0); }
          }
          @media (max-width: 600px) {
            #output { min-height: 260px; }
          }
        </style>
      </head>
      <body>
        <div class=\"terminal\">
          <header>
            <div class=\"dot\"></div>
            <h1>TweakKit Console</h1>
          </header>
          <div id=\"output\"></div>
          <div class=\"prompt\">
            <span>&gt;</span>
            <input id=\"input\" type=\"text\" autocomplete=\"off\" placeholder=\"Type a command...\" />
          </div>
        </div>
        <script>
          const output = document.getElementById('output');
          const input = document.getElementById('input');
          const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
          const socket = new WebSocket(`${scheme}://${location.host}/ws`);

          const writeLine = (text) => {
            const line = document.createElement('div');
            line.className = 'line';
            line.textContent = text;
            output.appendChild(line);
            output.scrollTop = output.scrollHeight;
          };

          const writeBlock = (text) => {
            text.split('\n').forEach((line) => writeLine(line));
          };

          socket.addEventListener('open', () => {
            writeLine('Connected to TweakKit server.');
          });

          socket.addEventListener('message', (event) => {
            writeBlock(event.data);
          });

          socket.addEventListener('close', () => {
            writeLine('Disconnected. Refresh to reconnect.');
          });

          input.addEventListener('keydown', (event) => {
            if (event.key !== 'Enter') return;
            const value = input.value.trim();
            if (!value) return;
            writeLine(`> ${value}`);
            socket.send(value);
            input.value = '';
          });
        </script>
      </body>
    </html>
    """
}
