import Foundation
import Telegraph
import TweakKitCore
import TweakKitNetworking

/// An MCP (Model Context Protocol) server embedded in your app, so AI agents such as
/// Claude Code can list and change tweaks in the running app.
///
/// Uses the MCP Streamable HTTP transport on a single endpoint (`POST /mcp`), returning
/// plain JSON responses. Requests must carry the server token, either as an
/// `Authorization: Bearer <token>` header (preferred) or a `?token=` query parameter.
///
/// ```swift
/// let mcp = TweakKitMCPServer()
/// try mcp.start()
/// // Prints a ready-to-paste `claude mcp add ...` command.
/// ```
public final class TweakKitMCPServer {
    public enum NetworkMode {
        /// Bind to 127.0.0.1 only. Use for the iOS Simulator and macOS apps.
        case localhostOnly
        /// Bind to all interfaces so a client on another machine (e.g. a Mac talking to
        /// an iPhone on the same Wi-Fi) can connect.
        case lan
    }

    public enum StartPolicy {
        /// Refuse to start outside DEBUG builds.
        case debugOnly
        /// Allow starting in release builds (e.g. internal TestFlight builds).
        case allowRelease
    }

    public enum ServerError: Error, CustomStringConvertible {
        case debugOnly

        public var description: String {
            switch self {
            case .debugOnly:
                return "TweakKitMCPServer is disabled outside DEBUG by default. Pass policy: .allowRelease to override."
            }
        }
    }

    public static let defaultPort = 8090
    public static let endpointPath = "/mcp"

    private let server: Server
    private let handler: MCPHandler
    private let lock = NSLock()
    private var routesConfigured = false
    private var activeNetworkMode: NetworkMode = .localhostOnly
    private var currentToken: String?

    public init(registry: TweakRegistry = .shared) {
        self.server = Server()
        self.handler = MCPHandler(registry: registry)
    }

    public var isRunning: Bool {
        server.isRunning
    }

    public var port: Int {
        server.port
    }

    /// The token clients must present. `nil` while stopped.
    public var token: String? {
        lock.locked { currentToken }
    }

    /// The MCP endpoint URL (without the token). `nil` while stopped.
    public var endpointURL: URL? {
        guard server.isRunning else {
            return nil
        }
        let host: String
        switch lock.locked({ activeNetworkMode }) {
        case .localhostOnly:
            host = "127.0.0.1"
        case .lan:
            host = NetworkAddress.lanIPv4Address() ?? "127.0.0.1"
        }
        return URL(string: "http://\(host):\(server.port)\(Self.endpointPath)")
    }

    /// A ready-to-run command that registers this server with Claude Code.
    public var claudeCodeCommand: String? {
        guard let endpointURL, let token else {
            return nil
        }
        return "claude mcp add --transport http tweakkit \(endpointURL.absoluteString) --header \"Authorization: Bearer \(token)\""
    }

    /// Starts the MCP server.
    ///
    /// - Parameters:
    ///   - port: TCP port to listen on. Defaults to 8090 so it can run alongside `TweakKitServer` on 8080.
    ///   - networkMode: `.localhostOnly` (default) or `.lan`.
    ///   - policy: `.debugOnly` (default) refuses to start in release builds.
    ///   - token: A fixed token to require. Pass a stable value (e.g. read from an environment
    ///     variable) so you don't have to re-register the server with your MCP client on every
    ///     launch. Defaults to a fresh random token.
    public func start(
        port: Int = TweakKitMCPServer.defaultPort,
        networkMode: NetworkMode = .localhostOnly,
        policy: StartPolicy = .debugOnly,
        token: String? = nil
    ) throws {
#if !DEBUG
        if policy == .debugOnly {
            throw ServerError.debugOnly
        }
#endif
        if !routesConfigured {
            configureRoutes()
            routesConfigured = true
        }
        let resolvedToken = (token?.isEmpty == false ? token : nil) ?? UUID().uuidString
        lock.locked {
            activeNetworkMode = networkMode
            currentToken = resolvedToken
        }
        let interface: String? = networkMode == .localhostOnly ? "127.0.0.1" : nil
        do {
            try server.start(port: port, interface: interface)
        } catch {
            lock.locked { currentToken = nil }
            throw error
        }
        if let endpointURL, let claudeCodeCommand {
            print("""
            TweakKitMCPServer running at \(endpointURL.absoluteString)
            Add it to Claude Code with:
              \(claudeCodeCommand)
            """)
        }
    }

    public func stop(immediately: Bool = false) {
        server.stop(immediately: immediately)
        lock.locked { currentToken = nil }
    }

    // MARK: - Routing

    private func configureRoutes() {
        server.route(.POST, Self.endpointPath) { [weak self] request in
            guard let self else {
                return HTTPResponse(.serviceUnavailable)
            }
            return self.handlePost(request)
        }

        // This server never pushes server-initiated messages, so it does not offer an SSE
        // stream (GET) and is stateless, so there is no session to DELETE.
        for method in [HTTPMethod.GET, .DELETE] {
            server.route(method, Self.endpointPath) { _ in
                var headers = HTTPHeaders.empty
                headers["Allow"] = "POST"
                return HTTPResponse(.methodNotAllowed, headers: headers)
            }
        }
    }

    private func handlePost(_ request: HTTPRequest) -> HTTPResponse {
        guard isAllowedOrigin(request) else {
            return HTTPResponse(.forbidden, content: "Forbidden origin")
        }
        guard isAuthorized(request) else {
            var headers = HTTPHeaders.empty
            headers["WWW-Authenticate"] = "Bearer"
            return HTTPResponse(.unauthorized, headers: headers, content: "Unauthorized")
        }
        guard let body = handler.handle(data: request.body) else {
            // Only notifications or responses were sent.
            return HTTPResponse(.accepted)
        }
        var headers = HTTPHeaders.empty
        headers.contentType = "application/json"
        return HTTPResponse(.ok, headers: headers, body: body)
    }

    // MARK: - Security

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        guard let expected = token else {
            return false
        }
        var presented: String?
        if let authorization = request.headers["Authorization"],
           authorization.lowercased().hasPrefix("bearer ") {
            presented = String(authorization.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
        } else {
            presented = request.uri.queryItems?.first(where: { $0.name == "token" })?.value
        }
        guard let presented else {
            return false
        }
        return Self.constantTimeEquals(presented, expected)
    }

    /// Guards against DNS-rebinding attacks from web pages, as the MCP spec requires.
    /// Non-browser clients (like Claude Code) don't send `Origin`, so they're unaffected.
    private func isAllowedOrigin(_ request: HTTPRequest) -> Bool {
        guard let origin = request.headers["Origin"] else {
            return true
        }
        guard let host = URLComponents(string: origin)?.host?.lowercased() else {
            return false
        }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard a.count == b.count else {
            return false
        }
        var difference: UInt8 = 0
        for index in a.indices {
            difference |= a[index] ^ b[index]
        }
        return difference == 0
    }
}

private extension NSLock {
    /// `NSLocking.withLock` needs iOS 16 / macOS 13; this package supports older versions.
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
