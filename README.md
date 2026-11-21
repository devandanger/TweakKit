# TweakKit

![CI](https://github.com/devandanger/TweakKit/actions/workflows/ci.yml/badge.svg)

Swift library for runtime tweaking of app values through a web-based terminal interface.

## Install

Add the package in Swift Package Manager:

- URL: `https://github.com/devandanger/TweakKit.git`
- Products: `TweakKitCore`, `TweakKitServer`, `TweakKitMCP`

## Core usage

Create tweaks and update values programmatically:

```swift
import TweakKitCore

let cornerRadius = Tweak<Double>(
    "ui.cornerRadius",
    defaultValue: 12,
    constraints: TweakConstraints(min: 0, max: 40, step: 1)
)

_ = cornerRadius.set(18, source: .code)
print(cornerRadius.currentValue)
```

Listen for change events:

```swift
let id = TweakRegistry.shared.addObserver { event in
    print("\(event.key): \(event.oldValueString) -> \(event.newValueString)")
}

// Later when you are done
TweakRegistry.shared.removeObserver(id)
```

## Server usage

Start the embedded server and open the printed URL:

```swift
import TweakKitServer

let server = TweakKitServer()
try server.start(port: 8080, networkMode: .localhostOnly)
```

The server prints a URL with a `token` query parameter. Use that URL in your browser.

### Web commands

- `help`
- `list [filter]`
- `get <key>`
- `set <key> <value>`
- `reset <key>`
- `reset-all`
- `last`
- `history [n]`
- `watch [key]`

## MCP usage

`TweakKitMCP` embeds an [MCP](https://modelcontextprotocol.io) server in your app, so AI agents such as Claude Code can inspect and change tweaks in the running app directly.

```swift
import TweakKitMCP

let mcp = TweakKitMCPServer()
try mcp.start() // localhost:8090, DEBUG builds only
```

On start it prints a ready-to-paste command:

```bash
claude mcp add --transport http tweakkit http://127.0.0.1:8090/mcp --header "Authorization: Bearer <token>"
```

The token is random on each launch by default. Pass a stable one so you only register once:

```swift
try mcp.start(token: ProcessInfo.processInfo.environment["TWEAKKIT_MCP_TOKEN"])
```

For a physical device, use `networkMode: .lan`; the printed URL uses the device's Wi-Fi address.

Tools: `list_tweaks`, `get_tweak`, `set_tweak`, `reset_tweak`, `reset_all_tweaks`, `get_tweak_history`. Changes made through MCP are recorded with source `mcp`.

It can run alongside `TweakKitServer` (port 8080). On iOS, sockets stop working when the app is suspended, so restart the server when the app returns to the foreground if needed.

## SwiftUI integration

SwiftUI property wrapper support is planned in Phase 4.
